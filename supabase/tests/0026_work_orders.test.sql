-- Tes pgTAP 0026: work order bengkel (T7.2)
-- Pola konsisten dengan purchase_orders: tulis hanya lewat RPC security definer.
begin;
select plan(18);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000031', 'authenticated', 'owner.wo@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000032', 'authenticated', 'kasir.wo@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000033', 'authenticated', 'admin.wo@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000034', 'authenticated', 'mekanik.wo@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000035', 'authenticated', 'owner2.wo@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('f2000000-0000-0000-0000-000000000031', 'Tenant WO A', 'bengkel'),
  ('f2000000-0000-0000-0000-000000000032', 'Tenant WO B', 'bengkel');

insert into public.outlets (id, tenant_id, name) values
  ('f3000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'Bengkel A'),
  ('f3000000-0000-0000-0000-000000000032', 'f2000000-0000-0000-0000-000000000032', 'Bengkel B');

insert into public.memberships (tenant_id, user_id, role) values
  ('f2000000-0000-0000-0000-000000000031', 'f1000000-0000-0000-0000-000000000031', 'owner'),
  ('f2000000-0000-0000-0000-000000000031', 'f1000000-0000-0000-0000-000000000032', 'kasir'),
  ('f2000000-0000-0000-0000-000000000031', 'f1000000-0000-0000-0000-000000000033', 'admin'),
  ('f2000000-0000-0000-0000-000000000031', 'f1000000-0000-0000-0000-000000000034', 'mekanik'),
  ('f2000000-0000-0000-0000-000000000032', 'f1000000-0000-0000-0000-000000000035', 'owner');

insert into public.customers (id, tenant_id, name, phone, active) values
  ('f6000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'Budi Santoso', '0821', true),
  ('f6000000-0000-0000-0000-000000000032', 'f2000000-0000-0000-0000-000000000032', 'Siti Rahayu', '0822', true);

insert into public.units (id, tenant_id, name) values
  ('f5000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'pcs'),
  ('f5000000-0000-0000-0000-000000000032', 'f2000000-0000-0000-0000-000000000031', 'sak');

insert into public.categories (id, tenant_id, name) values
  ('f6100000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'Sparepart');

insert into public.products (id, tenant_id, sku, barcode, name, category_id, kind, base_unit_id, track_stock, cost_price, sell_price, min_stock, active) values
  ('f7000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'SKU-OIL', '111', 'Oli Mesin', 'f6100000-0000-0000-0000-000000000031', 'barang', 'f5000000-0000-0000-0000-000000000031', true, 30000, 50000, 10, true),
  ('f7000000-0000-0000-0000-000000000032', 'f2000000-0000-0000-0000-000000000031', 'SKU-SERV', '222', 'Ganti Oli', 'f6100000-0000-0000-0000-000000000031', 'jasa', 'f5000000-0000-0000-0000-000000000031', false, 0, 150000, 0, true);

insert into public.product_units (id, tenant_id, product_id, unit_id, factor_to_base, sell_price, barcode) values
  ('f8000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'f7000000-0000-0000-0000-000000000031', 'f5000000-0000-0000-0000-000000000032', 40, 2000000, '999');

insert into public.vehicles (id, tenant_id, customer_id, plate_no, brand, model, year, last_odometer, active) values
  ('f9000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'f6000000-0000-0000-0000-000000000031', 'B 1234 ABC', 'Toyota', 'Avanza', 2018, 45000, true);

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

-- ════════════════════════════════════════════════════════════════════════════════
-- KASIR: baca boleh, buat WO via RPC ditolak (bukan owner/admin/mekanik)
-- ════════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000032');

select is(count(*)::int, 0, 'KASIR: melihat 0 WO') from public.work_orders;

select throws_ok(
  $q$ select public.create_work_order(
    'f2000000-0000-0000-0000-000000000031'::uuid,
    'f3000000-0000-0000-0000-000000000031'::uuid,
    'f6000000-0000-0000-0000-000000000031'::uuid,
    'f9000000-0000-0000-0000-000000000031'::uuid,
    45000,
    'Mobil berisik saat rem',
    null,
    null,
    0,
    '[{"product_id":"f7000000-0000-0000-0000-000000000032","unit_id":"f5000000-0000-0000-0000-000000000031","qty":1,"unit_price":150000}]'::jsonb
  ) $q$,
  '42501',
  'Tidak berhak membuat work order',
  'KASIR: buat WO via RPC ditolak'
);

select tests_set_postgres();
select is(count(*)::int, 0, 'VERIF: WO tetap 0') from public.work_orders;

-- ════════════════════════════════════════════════════════════════════════════════
-- MEKANIK: buat WO via RPC, total dihitung server, item tersimpan
-- ════════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000034');

with created as (
  select public.create_work_order(
    'f2000000-0000-0000-0000-000000000031'::uuid,
    'f3000000-0000-0000-0000-000000000031'::uuid,
    'f6000000-0000-0000-0000-000000000031'::uuid,
    'f9000000-0000-0000-0000-000000000031'::uuid,
    45000,
    'Mobil berisik saat rem',
    null,
    'f1000000-0000-0000-0000-000000000034',
    0,
    '[{"product_id":"f7000000-0000-0000-0000-000000000032","unit_id":"f5000000-0000-0000-0000-000000000031","qty":1,"unit_price":150000},{"product_id":"f7000000-0000-0000-0000-000000000031","unit_id":"f5000000-0000-0000-0000-000000000031","qty":2,"unit_price":50000}]'::jsonb
  ) as result
)
select is((result ->> 'idempotent')::boolean, false, 'MEKANIK: buat WO (idempotent false)') from created;

select tests_set_postgres();
select is(
  (select estimate_total from public.work_orders where wo_no like 'WO-%'),
  250000::bigint, 'VERIF: estimate_total = 150000 + 2*50000 = 250000'
);

select is(
  count(*)::int, 2, 'VERIF: item WO = 2 baris'
) from public.work_order_items;

-- ════════════════════════════════════════════════════════════════════════════════
-- MEKANIK: ubah status antri -> dikerjakan -> ditagih, lalu tidak boleh ubah lagi
-- ════════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000034');

with wo as (
  select id from public.work_orders where status = 'antri' limit 1
)
select is((public.update_work_order_status((select id from wo), 'dikerjakan') ->> 'status'), 'dikerjakan', 'MEKANIK: ubah status ke dikerjakan') from wo;

with wo as (
  select id from public.work_orders where status = 'dikerjakan' limit 1
)
select is((public.update_work_order_status((select id from wo), 'ditagih') ->> 'status'), 'ditagih', 'MEKANIK: ubah status ke ditagih') from wo;

select throws_ok(
  $q$ select public.update_work_order_status(
    (select id from public.work_orders where status = 'ditagih' limit 1),
    'selesai'
  ) $q$,
  'P0001',
  'Work order sudah ditagih: tidak boleh diubah',
  'MEKANIK: ubah WO sudah ditagih ditolak'
);

select tests_set_postgres();
select is(
  (select status from public.work_orders where wo_no like 'WO-%'),
  'ditagih', 'VERIF: status tetap ditagih'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- ISOLASI: owner tenant A tidak boleh buat WO di tenant B
-- ════════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000031');
select throws_ok(
  $q$ select public.create_work_order(
    'f2000000-0000-0000-0000-000000000032'::uuid,
    'f3000000-0000-0000-0000-000000000032'::uuid,
    'f6000000-0000-0000-0000-000000000032'::uuid,
    (select id from public.vehicles where tenant_id = 'f2000000-0000-0000-0000-000000000032' limit 1),
    10000,
    'Test isolasi',
    null,
    null,
    0,
    '[]'::jsonb
  ) $q$,
  '42501',
  'Tidak berhak membuat work order',
  'OWNER A: buat WO tenant B via RPC ditolak'
);

select is(
  count(*)::int, 0, 'OWNER A: tidak melihat WO tenant B'
) from public.work_orders where tenant_id = 'f2000000-0000-0000-0000-000000000032'::uuid;

-- ════════════════════════════════════════════════════════════════════════════════
-- CHECK: estimate_total negatif ditolak, qty <= 0 ditolak
-- ════════════════════════════════════════════════════════════════════════════════
select tests_set_postgres();
select throws_ok(
  $q$ insert into public.work_orders (tenant_id, outlet_id, wo_no, queue_no, customer_id, vehicle_id, complaint, status, estimate_total)
      values ('f2000000-0000-0000-0000-000000000031', 'f3000000-0000-0000-0000-000000000031', 'WO-NEG', 1, 'f6000000-0000-0000-0000-000000000031', 'f9000000-0000-0000-0000-000000000031', 'Test', 'antri', -5000) $q$,
  '23514',
  'new row for relation "work_orders" violates check constraint "work_orders_estimate_total_check"',
  'OWNER A: estimate_total negatif ditolak'
);

select is(
  count(*)::int, 0, 'VERIF: WO estimate_total negatif tidak tersimpan'
) from public.work_orders where wo_no = 'WO-NEG';

select tests_set_user('f1000000-0000-0000-0000-000000000034');
select throws_ok(
  $q$ select public.create_work_order(
    'f2000000-0000-0000-0000-000000000031'::uuid,
    'f3000000-0000-0000-0000-000000000031'::uuid,
    'f6000000-0000-0000-0000-000000000031'::uuid,
    'f9000000-0000-0000-0000-000000000031'::uuid,
    45000,
    'Test qty nol',
    null,
    null,
    0,
    '[{"product_id":"f7000000-0000-0000-0000-000000000032","unit_id":"f5000000-0000-0000-0000-000000000031","qty":0,"unit_price":150000}]'::jsonb
  ) $q$,
  'P0001',
  'Qty harus lebih dari 0',
  'MEKANIK: qty nol ditolak'
);

select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: WO tetap 1 baris (qty nol tidak membuat WO)'
) from public.work_orders;

-- ════════════════════════════════════════════════════════════════════════════════
-- tenant_id immutable: owner di dua tenant coba pindah WO antar-tenant (ditolak trigger)
-- ════════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000031');
select throws_ok(
  $q$ update public.work_orders
      set tenant_id = 'f2000000-0000-0000-0000-000000000032'
      where wo_no like 'WO-%' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel work_orders)',
  'OWNER: tenant_id WO tidak boleh berpindah'
);

select tests_set_postgres();
select is(
  (select tenant_id from public.work_orders where wo_no like 'WO-%'),
  'f2000000-0000-0000-0000-000000000031', 'VERIF: tenant_id WO tidak berpindah'
);

select * from finish();
rollback;
