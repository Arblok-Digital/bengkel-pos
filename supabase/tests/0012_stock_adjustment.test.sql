-- Tes pgTAP 0012: penyesuaian stok manual (RPC adjust_stock)
begin;
select plan(18);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'ab000000-0000-0000-0000-000000000001', 'authenticated', 'owner.adjust@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'ab000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.adjust@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'ab000000-0000-0000-0000-000000000003', 'authenticated', 'owner2.adjust@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('ab100000-0000-0000-0000-000000000001', 'Tenant Adjust A', 'bengkel'),
  ('ab100000-0000-0000-0000-000000000002', 'Tenant Adjust B', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('ab100000-0000-0000-0000-000000000001', 'ab000000-0000-0000-0000-000000000001', 'owner'),
  ('ab100000-0000-0000-0000-000000000001', 'ab000000-0000-0000-0000-000000000002', 'kasir'),
  ('ab100000-0000-0000-0000-000000000002', 'ab000000-0000-0000-0000-000000000003', 'owner');

insert into public.outlets (id, tenant_id, name) values
  ('ab200000-0000-0000-0000-000000000001', 'ab100000-0000-0000-0000-000000000001', 'Outlet A'),
  ('ab200000-0000-0000-0000-000000000002', 'ab100000-0000-0000-0000-000000000002', 'Outlet B');

insert into public.units (id, tenant_id, name) values
  ('ab300000-0000-0000-0000-000000000001', 'ab100000-0000-0000-0000-000000000001', 'pcs'),
  ('ab300000-0000-0000-0000-000000000002', 'ab100000-0000-0000-0000-000000000002', 'pcs');

insert into public.products (id, tenant_id, name, base_unit_id, kind, track_stock, sell_price)
values
  ('ab400000-0000-0000-0000-000000000001', 'ab100000-0000-0000-0000-000000000001',
   'Tracked', 'ab300000-0000-0000-0000-000000000001', 'barang', true, 10000),
  ('ab400000-0000-0000-0000-000000000002', 'ab100000-0000-0000-0000-000000000001',
   'Jasa', 'ab300000-0000-0000-0000-000000000001', 'jasa', false, 50000),
  ('ab400000-0000-0000-0000-000000000003', 'ab100000-0000-0000-0000-000000000002',
   'Tracked B', 'ab300000-0000-0000-0000-000000000002', 'barang', true, 10000);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note)
values ('ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000001',
        'ab200000-0000-0000-0000-000000000001', 10, 'adjustment', 'Stok awal');

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

-- (1) owner menambah 5
select tests_set_user('ab000000-0000-0000-0000-000000000001');
select is(
  (public.adjust_stock(
    'ab100000-0000-0000-0000-000000000001',
    'ab400000-0000-0000-0000-000000000001',
    'ab200000-0000-0000-0000-000000000001',
    5, 'Koreksi opname', 'ab500000-0000-0000-0000-000000000001')) is not null,
  true, 'ADJUST: owner menambah 5'
);

-- (2) stok menjadi 15
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'ab100000-0000-0000-0000-000000000001'
      and product_id = 'ab400000-0000-0000-0000-000000000001'),
  15::numeric, 'STOK: 10 + 5 = 15'
);

-- (3) movement bertambah
select is(
  count(*)::int, 2, 'MOVEMENT: 2 baris'
) from public.stock_movements
where tenant_id = 'ab100000-0000-0000-0000-000000000001';

-- (4) alasan tersimpan di note
select is(
  (select note from public.stock_movements
    where client_uuid = 'ab500000-0000-0000-0000-000000000001'),
  'Koreksi opname', 'MOVEMENT: alasan tersimpan'
);

-- (5) panggilan idempoten tidak error
select tests_set_user('ab000000-0000-0000-0000-000000000001');
select is(
  (public.adjust_stock(
    'ab100000-0000-0000-0000-000000000001',
    'ab400000-0000-0000-0000-000000000001',
    'ab200000-0000-0000-0000-000000000001',
    5, 'Koreksi opname', 'ab500000-0000-0000-0000-000000000001')) is not null,
  true, 'ADJUST: panggilan ulang tetap sukses'
);

-- (6) stok tidak berubah
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'ab100000-0000-0000-0000-000000000001'
      and product_id = 'ab400000-0000-0000-0000-000000000001'),
  15::numeric, 'VERIF: stok tetap 15 (idempoten)'
);

-- (7) movement tidak berganda
select is(
  count(*)::int, 2, 'VERIF: movement tetap 2'
) from public.stock_movements
where tenant_id = 'ab100000-0000-0000-0000-000000000001';

-- (8) kasir tidak boleh menyesuaikan stok
select tests_set_user('ab000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.adjust_stock(
        'ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000001',
        'ab200000-0000-0000-0000-000000000001',
        1, 'Coba kasir', 'ab500000-0000-0000-0000-000000000002') $q$,
  '42501',
  'Tidak berhak menyesuaikan stok',
  'KASIR: adjust ditolak'
);

-- (9) alasan kosong ditolak
select tests_set_user('ab000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.adjust_stock(
        'ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000001',
        'ab200000-0000-0000-0000-000000000001',
        1, '   ', 'ab500000-0000-0000-0000-000000000003') $q$,
  'P0001',
  'Alasan penyesuaian wajib diisi (minimal 3 karakter)',
  'ADJUST: alasan kosong ditolak'
);

-- (10) alasan terlalu pendek ditolak
select throws_ok(
  $q$ select public.adjust_stock(
        'ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000001',
        'ab200000-0000-0000-0000-000000000001',
        1, 'ab', 'ab500000-0000-0000-0000-000000000004') $q$,
  'P0001',
  'Alasan penyesuaian wajib diisi (minimal 3 karakter)',
  'ADJUST: alasan pendek ditolak'
);

-- (11) qty 0 ditolak
select throws_ok(
  $q$ select public.adjust_stock(
        'ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000001',
        'ab200000-0000-0000-0000-000000000001',
        0, 'Nol', 'ab500000-0000-0000-0000-000000000005') $q$,
  'P0001',
  'Qty penyesuaian tidak boleh 0',
  'ADJUST: qty 0 ditolak'
);

-- (12) client_uuid null ditolak
select throws_ok(
  $q$ select public.adjust_stock(
        'ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000001',
        'ab200000-0000-0000-0000-000000000001',
        1, 'Tanpa uuid', null) $q$,
  'P0001',
  'client_uuid wajib diisi',
  'ADJUST: client_uuid null ditolak'
);

-- (13) produk tidak melacak stok ditolak
select throws_ok(
  $q$ select public.adjust_stock(
        'ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000002',
        'ab200000-0000-0000-0000-000000000001',
        1, 'Jasa', 'ab500000-0000-0000-0000-000000000006') $q$,
  'P0001',
  'Produk ini tidak melacak stok',
  'ADJUST: produk non-stok ditolak'
);

-- (14) produk tidak ditemukan
select throws_ok(
  $q$ select public.adjust_stock(
        'ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000009',
        'ab200000-0000-0000-0000-000000000001',
        1, 'Tidak ada', 'ab500000-0000-0000-0000-000000000007') $q$,
  'P0001',
  'Produk tidak ditemukan',
  'ADJUST: produk tidak ditemukan ditolak'
);

-- (15) outlet tidak ditemukan
select throws_ok(
  $q$ select public.adjust_stock(
        'ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000001',
        'ab200000-0000-0000-0000-000000000009',
        1, 'Tidak ada', 'ab500000-0000-0000-0000-000000000008') $q$,
  'P0001',
  'Outlet tidak ditemukan',
  'ADJUST: outlet tidak ditemukan ditolak'
);

-- (16) owner tenant lain ditolak
select tests_set_user('ab000000-0000-0000-0000-000000000003');
select throws_ok(
  $q$ select public.adjust_stock(
        'ab100000-0000-0000-0000-000000000001',
        'ab400000-0000-0000-0000-000000000001',
        'ab200000-0000-0000-0000-000000000001',
        1, 'Lintas tenant', 'ab500000-0000-0000-0000-000000000009') $q$,
  '42501',
  'Tidak berhak menyesuaikan stok',
  'OWNER B: adjust tenant A ditolak'
);

-- (17) penyesuaian negatif mengurangi stok
select tests_set_user('ab000000-0000-0000-0000-000000000001');
select is(
  (public.adjust_stock(
    'ab100000-0000-0000-0000-000000000001',
    'ab400000-0000-0000-0000-000000000001',
    'ab200000-0000-0000-0000-000000000001',
    -20, 'Barang rusak', 'ab500000-0000-0000-0000-000000000010')) is not null,
  true, 'ADJUST: penyesuaian negatif diterima'
);

-- (18) stok bisa negatif & client_uuid tersimpan
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'ab100000-0000-0000-0000-000000000001'
      and product_id = 'ab400000-0000-0000-0000-000000000001'),
  (-5)::numeric, 'STOK: 15 - 20 = -5'
);

select * from finish();
rollback;
