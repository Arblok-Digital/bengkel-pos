-- Tes pgTAP 0011: stok — movements append-only, stock_levels via trigger, view
begin;
select plan(22);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'aa000000-0000-0000-0000-000000000001', 'authenticated', 'owner.stock@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'aa000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.stock@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'aa000000-0000-0000-0000-000000000003', 'authenticated', 'owner2.stock@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('aa100000-0000-0000-0000-000000000001', 'Tenant Stok A', 'bengkel'),
  ('aa100000-0000-0000-0000-000000000002', 'Tenant Stok B', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('aa100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'owner'),
  ('aa100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000002', 'kasir'),
  ('aa100000-0000-0000-0000-000000000002', 'aa000000-0000-0000-0000-000000000003', 'owner');

insert into public.outlets (id, tenant_id, name) values
  ('aa200000-0000-0000-0000-000000000001', 'aa100000-0000-0000-0000-000000000001', 'Outlet A'),
  ('aa200000-0000-0000-0000-000000000002', 'aa100000-0000-0000-0000-000000000002', 'Outlet B');

insert into public.units (id, tenant_id, name) values
  ('aa300000-0000-0000-0000-000000000001', 'aa100000-0000-0000-0000-000000000001', 'pcs'),
  ('aa300000-0000-0000-0000-000000000002', 'aa100000-0000-0000-0000-000000000002', 'pcs');

insert into public.products (id, tenant_id, name, base_unit_id, kind, sell_price, min_stock)
values
  ('aa400000-0000-0000-0000-000000000001', 'aa100000-0000-0000-0000-000000000001',
   'Oli Stok', 'aa300000-0000-0000-0000-000000000001', 'barang', 10000, 5),
  ('aa400000-0000-0000-0000-000000000002', 'aa100000-0000-0000-0000-000000000002',
   'Semen Stok', 'aa300000-0000-0000-0000-000000000002', 'barang', 60000, 5);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type)
values
  ('aa100000-0000-0000-0000-000000000001', 'aa400000-0000-0000-0000-000000000001',
   'aa200000-0000-0000-0000-000000000001', 10, 'adjustment'),
  ('aa100000-0000-0000-0000-000000000001', 'aa400000-0000-0000-0000-000000000001',
   'aa200000-0000-0000-0000-000000000001', -3, 'sale'),
  ('aa100000-0000-0000-0000-000000000001', 'aa400000-0000-0000-0000-000000000001',
   'aa200000-0000-0000-0000-000000000001', 2, 'purchase');

create or replace function tests_set_user(p_user uuid) returns void
  language plpgsql as $$
  begin
    execute format('set local "request.jwt.claims" to %L', json_build_object('sub', p_user, 'role', 'authenticated'));
    execute format('set local role %I', 'authenticated');
  end;
  $$;

create or replace function tests_set_postgres() returns void
  language plpgsql as $$
  begin
    execute 'reset request.jwt.claims';
    execute 'reset role';
  end;
  $$;

-- (1) trigger mengakumulasi movement
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'aa100000-0000-0000-0000-000000000001'
      and product_id = 'aa400000-0000-0000-0000-000000000001'
      and outlet_id = 'aa200000-0000-0000-0000-000000000001'),
  9::numeric, 'STOK: 10 - 3 + 2 = 9'
);

-- (2) kasir melihat stock level tenant-nya
select tests_set_user('aa000000-0000-0000-0000-000000000002');
select is(count(*)::int, 1, 'KASIR: melihat 1 stock level') from public.stock_levels;

-- (3) kasir tidak bisa update stock_levels
select throws_ok(
  $q$ update public.stock_levels set qty_base = 999 $q$,
  '42501',
  'permission denied for table stock_levels',
  'KASIR: update stock_levels ditolak'
);

-- (4) verifikasi stok tidak berubah
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where product_id = 'aa400000-0000-0000-0000-000000000001'),
  9::numeric, 'VERIF: stok tetap 9'
);

-- (5) kasir tidak bisa insert stock_levels
select tests_set_user('aa000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ insert into public.stock_levels (tenant_id, product_id, outlet_id, qty_base)
      values ('aa100000-0000-0000-0000-000000000001',
              'aa400000-0000-0000-0000-000000000001',
              'aa200000-0000-0000-0000-000000000001', 1) $q$,
  '42501',
  'permission denied for table stock_levels',
  'KASIR: insert stock_levels ditolak'
);

-- (6) kasir tidak bisa delete stock_levels
select throws_ok(
  $q$ delete from public.stock_levels $q$,
  '42501',
  'permission denied for table stock_levels',
  'KASIR: delete stock_levels ditolak'
);

-- (7) kasir tidak bisa insert movement langsung
select throws_ok(
  $q$ insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type)
      values ('aa100000-0000-0000-0000-000000000001',
              'aa400000-0000-0000-0000-000000000001',
              'aa200000-0000-0000-0000-000000000001', 1, 'adjustment') $q$,
  '42501',
  'permission denied for table stock_movements',
  'KASIR: insert movement langsung ditolak'
);

-- (8) kasir melihat movement tenant-nya
select is(count(*)::int, 3, 'KASIR: melihat 3 movement') from public.stock_movements;

-- (9) owner tidak bisa update movement
select tests_set_user('aa000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ update public.stock_movements set qty_base = 1 $q$,
  '42501',
  'permission denied for table stock_movements',
  'OWNER: update movement ditolak'
);

-- (10) owner tidak bisa delete movement
select throws_ok(
  $q$ delete from public.stock_movements $q$,
  '42501',
  'permission denied for table stock_movements',
  'OWNER: delete movement ditolak'
);

-- (11) postgres pun tidak bisa update movement (append-only)
select tests_set_postgres();
select throws_ok(
  $q$ update public.stock_movements set qty_base = 1 $q$,
  'P0001',
  'stock_movements bersifat append-only (koreksi lewat movement balik)',
  'DB: update movement ditolak trigger'
);

-- (12) postgres pun tidak bisa delete movement
select throws_ok(
  $q$ delete from public.stock_movements $q$,
  'P0001',
  'stock_movements bersifat append-only (koreksi lewat movement balik)',
  'DB: delete movement ditolak trigger'
);

-- (13) tenant B tidak melihat stock level tenant A
select tests_set_user('aa000000-0000-0000-0000-000000000003');
select is(count(*)::int, 0, 'OWNER B: stock level tenant A tidak terlihat')
from public.stock_levels;

-- (14) tenant B tidak melihat movement tenant A
select is(count(*)::int, 0, 'OWNER B: movement tenant A tidak terlihat')
from public.stock_movements;

-- (15) produk & outlet beda tenant ditolak FK
select tests_set_postgres();
select throws_ok(
  $q$ insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type)
      values ('aa100000-0000-0000-0000-000000000001',
              'aa400000-0000-0000-0000-000000000001',
              'aa200000-0000-0000-0000-000000000002', 1, 'adjustment') $q$,
  '23503',
  'insert or update on table "stock_movements" violates foreign key constraint "stock_movements_outlet_same_tenant"',
  'DB: outlet tenant B untuk produk tenant A ditolak'
);

-- (16) view stok: qty
select tests_set_user('aa000000-0000-0000-0000-000000000002');
select is(
  (select qty_base from public.stock_by_outlet
    where product_id = 'aa400000-0000-0000-0000-000000000001'),
  9::numeric, 'VIEW: qty stok 9'
);

-- (17) view stok: belum menipis (min 5)
select is(
  (select is_low from public.stock_by_outlet
    where product_id = 'aa400000-0000-0000-0000-000000000001'),
  false, 'VIEW: stok 9 belum menipis'
);

-- (18) movement keluar 5 → stok 4
select tests_set_postgres();
with inserted as (
  insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type)
  values ('aa100000-0000-0000-0000-000000000001',
          'aa400000-0000-0000-0000-000000000001',
          'aa200000-0000-0000-0000-000000000001', -5, 'adjustment')
  returning id
)
select is(count(*)::int, 1, 'DB: movement keluar 5 diterima') from inserted;

-- (19) view stok: qty 4
select tests_set_user('aa000000-0000-0000-0000-000000000002');
select is(
  (select qty_base from public.stock_by_outlet
    where product_id = 'aa400000-0000-0000-0000-000000000001'),
  4::numeric, 'VIEW: qty stok 4'
);

-- (20) view stok: menipis
select is(
  (select is_low from public.stock_by_outlet
    where product_id = 'aa400000-0000-0000-0000-000000000001'),
  true, 'VIEW: stok 4 menipis (min 5)'
);

-- (21) qty 0 ditolak
select tests_set_postgres();
select throws_ok(
  $q$ insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type)
      values ('aa100000-0000-0000-0000-000000000001',
              'aa400000-0000-0000-0000-000000000001',
              'aa200000-0000-0000-0000-000000000001', 0, 'adjustment') $q$,
  '23514',
  'new row for relation "stock_movements" violates check constraint "stock_movements_qty_base_check"',
  'DB: qty 0 ditolak'
);

-- (22) tipe movement tidak valid ditolak
select throws_ok(
  $q$ insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type)
      values ('aa100000-0000-0000-0000-000000000001',
              'aa400000-0000-0000-0000-000000000001',
              'aa200000-0000-0000-0000-000000000001', 1, 'entah') $q$,
  '23514',
  'new row for relation "stock_movements" violates check constraint "stock_movements_type_check"',
  'DB: tipe movement tidak valid ditolak'
);

select * from finish();
rollback;
