-- Tes pgTAP 0008: produk (T2.2)
-- Cakupan: RLS, isolasi tenant, cost_price tidak bisa dibaca/ditulis API,
-- unique SKU/barcode per tenant, FK kategori/satuan lintas tenant, guard trigger.

begin;
select plan(30);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000001', 'authenticated', 'owner.prod@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.prod@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000003', 'authenticated', 'admin.prod@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000004', 'authenticated', 'owner2.prod@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('d2000000-0000-0000-0000-000000000001', 'Tenant Produk A', 'bengkel'),
  ('d2000000-0000-0000-0000-000000000002', 'Tenant Produk B', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'owner'),
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'kasir'),
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000003', 'admin'),
  ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000004', 'owner');

insert into public.categories (id, tenant_id, name) values
  ('d3000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'Oli'),
  ('d3000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000002', 'Material');

insert into public.units (id, tenant_id, name) values
  ('d4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'pcs'),
  ('d4000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000002', 'sak');

insert into public.products (id, tenant_id, name, sku, barcode, category_id, base_unit_id, kind, sell_price, min_stock)
values
  ('d5000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
   'Oli Mesin', 'OLI-1', '8990001', 'd3000000-0000-0000-0000-000000000001',
   'd4000000-0000-0000-0000-000000000001', 'barang', 50000, 2),
  ('d5000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000002',
   'Semen 50kg', 'SEMEN-1', '8990002', 'd3000000-0000-0000-0000-000000000002',
   'd4000000-0000-0000-0000-000000000002', 'barang', 65000, 5);

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

-- ══════════════════════════════════════════════════════════════════════════
-- KASIR: baca kolom aman; cost_price & tulis ditolak
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('d1000000-0000-0000-0000-000000000002');

-- (1) kasir melihat produk tenant-nya
select is(count(id)::int, 1, 'KASIR: melihat 1 produk') from public.products;

-- (2) kasir bisa baca kolom aman
select is(
  (select name from public.products where id = 'd5000000-0000-0000-0000-000000000001'),
  'Oli Mesin', 'KASIR: baca nama produk'
);

-- (3) kasir tidak bisa baca cost_price
select throws_ok(
  $q$ select cost_price from public.products $q$,
  '42501',
  'permission denied for table products',
  'KASIR: cost_price tidak bisa dibaca'
);

-- (4) kasir tidak bisa insert produk
select throws_ok(
  $q$ insert into public.products (tenant_id, name, base_unit_id, sell_price)
      values ('d2000000-0000-0000-0000-000000000001', 'Produk Kasir',
              'd4000000-0000-0000-0000-000000000001', 1000) $q$,
  '42501',
  'new row violates row-level security policy for table "products"',
  'KASIR: insert produk ditolak'
);

-- (5) verifikasi jumlah produk
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: produk tenant A tetap 1'
) from public.products where tenant_id = 'd2000000-0000-0000-0000-000000000001';

-- (6) kasir tidak bisa update produk (0 baris)
select tests_set_user('d1000000-0000-0000-0000-000000000002');
with updated as (
  update public.products set sell_price = 1
  where id = 'd5000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: update produk (0 baris)') from updated;

-- (7) verifikasi harga tidak berubah
select tests_set_postgres();
select is(
  (select sell_price from public.products where id = 'd5000000-0000-0000-0000-000000000001'),
  50000::bigint, 'VERIF: harga produk tidak berubah'
);

-- (8) kasir tidak bisa delete produk (0 baris)
select tests_set_user('d1000000-0000-0000-0000-000000000002');
with deleted as (
  delete from public.products
  where id = 'd5000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: delete produk (0 baris)') from deleted;

-- (9) verifikasi produk masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: produk Oli Mesin masih ada'
) from public.products where id = 'd5000000-0000-0000-0000-000000000001';

-- (10) owner pun tidak bisa baca cost_price lewat API
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select cost_price from public.products $q$,
  '42501',
  'permission denied for table products',
  'OWNER: cost_price tidak bisa dibaca via API'
);

-- ══════════════════════════════════════════════════════════════════════════
-- OWNER: CRUD
-- ══════════════════════════════════════════════════════════════════════════
-- (11) owner insert produk
with inserted as (
  insert into public.products (id, tenant_id, name, sku, barcode, category_id, base_unit_id, kind, sell_price, min_stock)
  values ('d5000000-0000-0000-0000-000000000003',
          'd2000000-0000-0000-0000-000000000001', 'Filter Oli', 'FLT-1', '8990003',
          'd3000000-0000-0000-0000-000000000001',
          'd4000000-0000-0000-0000-000000000001', 'barang', 35000, 1)
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert produk (1 baris)') from inserted;

-- (12) verifikasi produk baru
select tests_set_postgres();
select is(
  (select name from public.products where id = 'd5000000-0000-0000-0000-000000000003'),
  'Filter Oli', 'VERIF: produk baru tersimpan'
);

-- (13) owner update produk
select tests_set_user('d1000000-0000-0000-0000-000000000001');
with updated as (
  update public.products set name = 'Filter Oli Premium', sell_price = 40000
  where id = 'd5000000-0000-0000-0000-000000000003'
  returning id
)
select is(count(*)::int, 1, 'OWNER: update produk (1 baris)') from updated;

-- (14) verifikasi update
select tests_set_postgres();
select is(
  (select name from public.products where id = 'd5000000-0000-0000-0000-000000000003'),
  'Filter Oli Premium', 'VERIF: nama produk berubah'
);

-- (15) owner delete produk
select tests_set_user('d1000000-0000-0000-0000-000000000001');
with deleted as (
  delete from public.products
  where id = 'd5000000-0000-0000-0000-000000000003'
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete produk (1 baris)') from deleted;

-- (16) verifikasi produk hilang
select tests_set_postgres();
select is(
  count(*)::int, 0, 'VERIF: produk Filter Oli Premium hilang'
) from public.products where id = 'd5000000-0000-0000-0000-000000000003';

-- ══════════════════════════════════════════════════════════════════════════
-- UNIQUE, ISOLASI, FK, GUARD
-- ══════════════════════════════════════════════════════════════════════════
-- (17) SKU duplikat dalam tenant ditolak
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ insert into public.products (tenant_id, name, sku, base_unit_id)
      values ('d2000000-0000-0000-0000-000000000001', 'Duplikat SKU', 'OLI-1',
              'd4000000-0000-0000-0000-000000000001') $q$,
  '23505',
  'duplicate key value violates unique constraint "products_tenant_sku_key"',
  'OWNER: SKU duplikat ditolak'
);

-- (18) barcode duplikat dalam tenant ditolak
select throws_ok(
  $q$ insert into public.products (tenant_id, name, barcode, base_unit_id)
      values ('d2000000-0000-0000-0000-000000000001', 'Duplikat Barcode', '8990001',
              'd4000000-0000-0000-0000-000000000001') $q$,
  '23505',
  'duplicate key value violates unique constraint "products_tenant_barcode_key"',
  'OWNER: barcode duplikat ditolak'
);

-- (19) SKU yang sama di tenant lain boleh
select tests_set_user('d1000000-0000-0000-0000-000000000004');
with inserted as (
  insert into public.products (tenant_id, name, sku, base_unit_id)
  values ('d2000000-0000-0000-0000-000000000002', 'Oli Tenant B', 'OLI-1',
          'd4000000-0000-0000-0000-000000000002')
  returning id
)
select is(count(*)::int, 1, 'OWNER B: SKU sama di tenant berbeda boleh') from inserted;

-- (20) owner A tidak bisa insert produk ke tenant B
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ insert into public.products (tenant_id, name, base_unit_id)
      values ('d2000000-0000-0000-0000-000000000002', 'Produk Bajakan',
              'd4000000-0000-0000-0000-000000000002') $q$,
  '42501',
  'new row violates row-level security policy for table "products"',
  'OWNER A: insert produk tenant B ditolak'
);

-- (21) owner A tidak melihat produk tenant B
select is(
  count(id)::int, 0, 'OWNER A: tidak melihat produk tenant B'
) from public.products where tenant_id = 'd2000000-0000-0000-0000-000000000002';

-- (22) kategori tenant lain ditolak FK
select throws_ok(
  $q$ insert into public.products (tenant_id, name, category_id, base_unit_id)
      values ('d2000000-0000-0000-0000-000000000001', 'Kategori Nyasar',
              'd3000000-0000-0000-0000-000000000002',
              'd4000000-0000-0000-0000-000000000001') $q$,
  '23503',
  'insert or update on table "products" violates foreign key constraint "products_category_same_tenant"',
  'OWNER A: kategori tenant B ditolak'
);

-- (23) satuan tenant lain ditolak FK
select throws_ok(
  $q$ insert into public.products (tenant_id, name, base_unit_id)
      values ('d2000000-0000-0000-0000-000000000001', 'Satuan Nyasar',
              'd4000000-0000-0000-0000-000000000002') $q$,
  '23503',
  'insert or update on table "products" violates foreign key constraint "products_unit_same_tenant"',
  'OWNER A: satuan tenant B ditolak'
);

-- (24) tenant_id tidak bisa dipindah (kolom tenant_id tidak di-grant untuk UPDATE)
select throws_ok(
  $q$ update public.products set tenant_id = 'd2000000-0000-0000-0000-000000000002'
      where id = 'd5000000-0000-0000-0000-000000000001' $q$,
  '42501',
  'permission denied for table products',
  'OWNER A: pindah tenant_id produk ditolak (kolom tidak di-grant)'
);

-- (25) verifikasi produk tetap di tenant A
select tests_set_postgres();
select is(
  (select tenant_id from public.products
    where id = 'd5000000-0000-0000-0000-000000000001'),
  'd2000000-0000-0000-0000-000000000001'::uuid,
  'VERIF: produk tetap di tenant A'
);

-- (26) kind tidak valid
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ insert into public.products (tenant_id, name, base_unit_id, kind)
      values ('d2000000-0000-0000-0000-000000000001', 'Kind Salah',
              'd4000000-0000-0000-0000-000000000001', 'jasa_x') $q$,
  '23514',
  'new row for relation "products" violates check constraint "products_kind_check"',
  'OWNER A: kind tidak valid ditolak'
);

-- (27) harga jual negatif ditolak
select throws_ok(
  $q$ insert into public.products (tenant_id, name, base_unit_id, sell_price)
      values ('d2000000-0000-0000-0000-000000000001', 'Harga Minus',
              'd4000000-0000-0000-0000-000000000001', -1) $q$,
  '23514',
  'new row for relation "products" violates check constraint "products_sell_price_check"',
  'OWNER A: harga negatif ditolak'
);

-- (28) cost_price tidak bisa ditulis via API
select throws_ok(
  $q$ insert into public.products (tenant_id, name, base_unit_id, cost_price)
      values ('d2000000-0000-0000-0000-000000000001', 'HPP Nyasar',
              'd4000000-0000-0000-0000-000000000001', 1000) $q$,
  '42501',
  'permission denied for table products',
  'OWNER A: cost_price tidak bisa ditulis via API'
);

-- (29) admin boleh insert produk
select tests_set_user('d1000000-0000-0000-0000-000000000003');
with inserted as (
  insert into public.products (id, tenant_id, name, base_unit_id, sell_price)
  values ('d5000000-0000-0000-0000-000000000004',
          'd2000000-0000-0000-0000-000000000001', 'Jasa Servis',
          'd4000000-0000-0000-0000-000000000001', 75000)
  returning id
)
select is(count(*)::int, 1, 'ADMIN: insert produk (1 baris)') from inserted;

-- (30) verifikasi produk admin
select tests_set_postgres();
select is(
  (select name from public.products where id = 'd5000000-0000-0000-0000-000000000004'),
  'Jasa Servis', 'VERIF: produk admin tersimpan'
);

select * from finish();
rollback;
