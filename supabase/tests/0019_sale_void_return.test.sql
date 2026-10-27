-- Tes pgTAP 0019: void & retur penjualan
begin;
select plan(29);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000001', 'authenticated', 'owner.void@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.void@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000003', 'authenticated', 'owner2.void@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('d2000000-0000-0000-0000-000000000001', 'Tenant Void A', 'bengkel'),
  ('d2000000-0000-0000-0000-000000000002', 'Tenant Void B', 'bengkel');

insert into public.memberships (tenant_id, user_id, role) values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'owner'),
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'kasir'),
  ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', 'owner');

insert into public.outlets (id, tenant_id, name)
values ('d3000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'Outlet Void');

insert into public.units (id, tenant_id, name)
values ('d4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'pcs');

insert into public.products (id, tenant_id, name, base_unit_id, kind, track_stock, sell_price, cost_price)
values ('d5000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
        'Barang Void', 'd4000000-0000-0000-0000-000000000001', 'barang', true, 10000, 6000);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note)
values ('d2000000-0000-0000-0000-000000000001',
        'd5000000-0000-0000-0000-000000000001',
        'd3000000-0000-0000-0000-000000000001', 10, 'adjustment', 'Stok awal');

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

-- Sale 1: 2 pcs
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select is(
  (public.create_sale(
    'e1000000-0000-0000-0000-000000000001',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    null,
    jsonb_build_array(jsonb_build_object(
      'product_id', 'd5000000-0000-0000-0000-000000000001',
      'unit_id', 'd4000000-0000-0000-0000-000000000001',
      'qty', 2, 'unit_price', 10000, 'discount', 0)),
    '[{"method":"tunai","amount":20000}]'::jsonb,
    null, null, null, null)
  ->> 'sale_id') is not null,
  true, 'SALE 1: 2 pcs dibuat'
);

-- (1) Kasir tidak boleh void
select tests_set_user('d1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.void_sale(
        (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000001'),
        'Salah input', 'e2000000-0000-0000-0000-000000000001') $q$,
  '42501',
  'Tidak berhak void penjualan',
  'KASIR: void ditolak'
);

-- (2) Kasir tidak boleh retur
select throws_ok(
  $q$ select public.create_sale_return(
        (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000001'),
        (select jsonb_agg(jsonb_build_object('sale_item_id', id, 'qty', 1))
         from public.sale_items
         where sale_id = (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000001')),
        'Barang rusak', 'e2000000-0000-0000-0000-000000000002') $q$,
  '42501',
  'Tidak berhak membuat retur',
  'KASIR: retur ditolak'
);

-- (3) Owner void sale 1
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select is(
  (public.void_sale(
    (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000001'),
    'Salah input qty', 'e2000000-0000-0000-0000-000000000003')
  ->> 'status'),
  'void', 'OWNER: void berhasil'
);

-- (4) Verifikasi status + alasan
select tests_set_postgres();
select is(
  (select (status, void_reason, voided_at is not null)
     from public.sales
     where client_uuid = 'e1000000-0000-0000-0000-000000000001'),
  ('void'::text, 'Salah input qty'::text, true),
  'VERIF: status void + alasan tersimpan'
);

-- (5) Stok kembali 10
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'd2000000-0000-0000-0000-000000000001'
      and product_id = 'd5000000-0000-0000-0000-000000000001'
      and outlet_id = 'd3000000-0000-0000-0000-000000000001'),
  10::numeric, 'STOK: kembali 10 setelah void'
);

-- (6) Movement balik tercatat
select is(
  (select count(*)::int from public.stock_movements
    where tenant_id = 'd2000000-0000-0000-0000-000000000001'
      and ref_type = 'sale_void'
      and qty_base = 2),
  1, 'MOVEMENT: +2 dari void'
);

-- (7) Audit log void
select is(
  (select count(*)::int from public.audit_logs
    where tenant_id = 'd2000000-0000-0000-0000-000000000001'
      and action = 'void'),
  1, 'AUDIT: void tercatat'
);

-- (8) Idempoten dengan client_uuid sama
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select lives_ok(
  $q$ select public.void_sale(
        (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000001'),
        'Salah input qty', 'e2000000-0000-0000-0000-000000000003') $q$,
  'OWNER: void ulang client_uuid sama tidak error'
);

-- (9) Movement tidak dobel
select tests_set_postgres();
select is(
  (select count(*)::int from public.stock_movements
    where tenant_id = 'd2000000-0000-0000-0000-000000000001'
      and ref_type = 'sale_void'),
  1, 'VERIF: movement void tidak dobel'
);

-- (10) Void ulang dengan client_uuid lain ditolak
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.void_sale(
        (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000001'),
        'Coba lagi', 'e2000000-0000-0000-0000-000000000004') $q$,
  'P0001',
  'Penjualan sudah di-void',
  'VOID: void kedua dengan uuid lain ditolak'
);

-- (11) Retur pada penjualan void ditolak
select throws_ok(
  $q$ select public.create_sale_return(
        (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000001'),
        (select jsonb_agg(jsonb_build_object('sale_item_id', id, 'qty', 1))
         from public.sale_items
         where sale_id = (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000001')),
        'Barang rusak', 'e2000000-0000-0000-0000-000000000005') $q$,
  'P0001',
  'Penjualan sudah di-void, tidak bisa diretur',
  'RETUR: penjualan void tidak bisa diretur'
);

-- Sale 2: 2 pcs untuk retur
select is(
  (public.create_sale(
    'e1000000-0000-0000-0000-000000000002',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    null,
    jsonb_build_array(jsonb_build_object(
      'product_id', 'd5000000-0000-0000-0000-000000000001',
      'unit_id', 'd4000000-0000-0000-0000-000000000001',
      'qty', 2, 'unit_price', 10000, 'discount', 0)),
    '[{"method":"tunai","amount":20000}]'::jsonb,
    null, null, null, null)
  ->> 'sale_id') is not null,
  true, 'SALE 2: 2 pcs dibuat'
);

-- (12) Retur 1 pcs
select is(
  (public.create_sale_return(
    (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000002'),
    (select jsonb_build_array(jsonb_build_object('sale_item_id', id, 'qty', 1))
     from public.sale_items
     where sale_id = (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000002')),
    'Barang rusak', 'e2000000-0000-0000-0000-000000000006')
  ->> 'total')::bigint,
  10000::bigint, 'RETUR: total retur 10000'
);

-- (13) Stok menjadi 9
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'd2000000-0000-0000-0000-000000000001'
      and product_id = 'd5000000-0000-0000-0000-000000000001'
      and outlet_id = 'd3000000-0000-0000-0000-000000000001'),
  9::numeric, 'STOK: 10 - 2 + 1 = 9'
);

-- (14) Movement retur +1
select is(
  (select count(*)::int from public.stock_movements
    where tenant_id = 'd2000000-0000-0000-0000-000000000001'
      and ref_type = 'sale_return'
      and qty_base = 1),
  1, 'MOVEMENT: +1 dari retur'
);

-- (15) Retur melebihi sisa ditolak
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.create_sale_return(
        (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000002'),
        (select jsonb_build_array(jsonb_build_object('sale_item_id', id, 'qty', 5))
         from public.sale_items
         where sale_id = (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000002')),
        'Retur berlebih', 'e2000000-0000-0000-0000-000000000007') $q$,
  'P0001',
  'Qty retur melebihi sisa (terjual 2, sudah retur 1)',
  'RETUR: qty melebihi sisa ditolak'
);

-- (16) Stok tidak berubah setelah penolakan
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'd2000000-0000-0000-0000-000000000001'
      and product_id = 'd5000000-0000-0000-0000-000000000001'
      and outlet_id = 'd3000000-0000-0000-0000-000000000001'),
  9::numeric, 'VERIF: stok tetap 9 setelah retur ditolak'
);

-- (17) Idempoten retur dengan client_uuid sama
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select lives_ok(
  $q$ select public.create_sale_return(
        (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000002'),
        (select jsonb_build_array(jsonb_build_object('sale_item_id', id, 'qty', 1))
         from public.sale_items
         where sale_id = (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000002')),
        'Barang rusak', 'e2000000-0000-0000-0000-000000000006') $q$,
  'RETUR: panggilan ulang client_uuid sama tidak error'
);

-- (18) Retur tidak dobel
select tests_set_postgres();
select is(
  (select count(*)::int from public.sale_returns
    where tenant_id = 'd2000000-0000-0000-0000-000000000001'),
  1, 'VERIF: tetap 1 retur'
);

-- (19) Void setelah ada retur ditolak
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.void_sale(
        (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000002'),
        'Batal semua', 'e2000000-0000-0000-0000-000000000008') $q$,
  'P0001',
  'Penjualan sudah memiliki retur, tidak bisa di-void',
  'VOID: penjualan yang sudah diretur tidak bisa void'
);

-- (20) Owner tenant B tidak boleh void
select tests_set_postgres();
create temp table void_sale2_id (id uuid);
insert into void_sale2_id
  select id from public.sales
  where client_uuid = 'e1000000-0000-0000-0000-000000000002';
create temp table void_item2 (id uuid);
insert into void_item2
  select id from public.sale_items
  where sale_id = (select id from void_sale2_id);
grant select on void_sale2_id, void_item2 to authenticated;

select tests_set_user('d1000000-0000-0000-0000-000000000003');
select throws_ok(
  $q$ select public.void_sale(
        (select id from void_sale2_id),
        'Coba lintas tenant', 'e2000000-0000-0000-0000-000000000009') $q$,
  '42501',
  'Tidak berhak void penjualan',
  'OWNER B: void tenant A ditolak'
);

-- (21) Owner tenant B tidak boleh retur
select throws_ok(
  $q$ select public.create_sale_return(
        (select id from void_sale2_id),
        jsonb_build_array(jsonb_build_object(
          'sale_item_id', (select id from void_item2), 'qty', 1)),
        'Coba lintas tenant', 'e2000000-0000-0000-0000-00000000000a') $q$,
  '42501',
  'Tidak berhak membuat retur',
  'OWNER B: retur tenant A ditolak'
);

-- (22) Insert langsung ke sale_returns ditolak
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ insert into public.sale_returns (tenant_id, sale_id, reason, client_uuid)
      values ('d2000000-0000-0000-0000-000000000001',
              (select id from public.sales limit 1), 'Langsung',
              'e2000000-0000-0000-0000-00000000000b') $q$,
  '42501',
  'permission denied for table sale_returns',
  'RLS: insert retur langsung ditolak'
);

-- (23) tenant_id retur tidak bisa diubah
select tests_set_postgres();
select throws_ok(
  $q$ update public.sale_returns
      set tenant_id = 'd2000000-0000-0000-0000-000000000002'
      where tenant_id = 'd2000000-0000-0000-0000-000000000001' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel sale_returns)',
  'DB: tenant_id retur immutable'
);

-- Sale 3 untuk uji alasan pendek
select tests_set_user('d1000000-0000-0000-0000-000000000001');
select is(
  (public.create_sale(
    'e1000000-0000-0000-0000-000000000003',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    null,
    jsonb_build_array(jsonb_build_object(
      'product_id', 'd5000000-0000-0000-0000-000000000001',
      'unit_id', 'd4000000-0000-0000-0000-000000000001',
      'qty', 1, 'unit_price', 10000, 'discount', 0)),
    '[{"method":"tunai","amount":10000}]'::jsonb,
    null, null, null, null)
  ->> 'sale_id') is not null,
  true, 'SALE 3: 1 pcs dibuat'
);

-- (24) Alasan void terlalu pendek ditolak
select throws_ok(
  $q$ select public.void_sale(
        (select id from public.sales where client_uuid = 'e1000000-0000-0000-0000-000000000003'),
        'ab', 'e2000000-0000-0000-0000-00000000000c') $q$,
  'P0001',
  'Alasan void wajib diisi (minimal 3 karakter)',
  'VOID: alasan pendek ditolak'
);

-- (25) Stok tetap 8 setelah void ditolak
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'd2000000-0000-0000-0000-000000000001'
      and product_id = 'd5000000-0000-0000-0000-000000000001'
      and outlet_id = 'd3000000-0000-0000-0000-000000000001'),
  8::numeric, 'VERIF: stok 8 setelah void alasan pendek ditolak'
);

-- (26) Status sale 3 tetap paid
select is(
  (select status from public.sales
    where client_uuid = 'e1000000-0000-0000-0000-000000000003'),
  'paid'::text, 'VERIF: status tetap paid'
);

select * from finish();
rollback;
