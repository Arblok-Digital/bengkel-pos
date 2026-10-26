-- Tes pgTAP 0018: shift_expected_cash (dipakai UI + close_cash_shift)
begin;
select plan(10);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000001', 'authenticated', 'kasir.exp@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000002', 'authenticated', 'owner2.exp@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('c2000000-0000-0000-0000-000000000001', 'Tenant Exp A', 'bengkel'),
  ('c2000000-0000-0000-0000-000000000002', 'Tenant Exp B', 'bengkel');

insert into public.memberships (tenant_id, user_id, role) values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'kasir'),
  ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000002', 'owner');

insert into public.outlets (id, tenant_id, name)
values ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'Outlet Exp');

insert into public.units (id, tenant_id, name)
values ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'pcs');

insert into public.products (id, tenant_id, name, base_unit_id, kind, track_stock, sell_price, cost_price)
values ('c5000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
        'Barang Exp', 'c4000000-0000-0000-0000-000000000001', 'barang', true, 10000, 5000);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note)
values ('c2000000-0000-0000-0000-000000000001',
        'c5000000-0000-0000-0000-000000000001',
        'c3000000-0000-0000-0000-000000000001', 50, 'adjustment', 'Stok awal');

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

-- Buka shift modal 100000
select tests_set_user('c1000000-0000-0000-0000-000000000001');
select is(
  (public.open_cash_shift(
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    100000, 'c6000000-0000-0000-0000-000000000001')) is not null,
  true, 'SHIFT: buka 100000'
);

-- (1) Tanpa penjualan, expected = modal awal
select is(
  public.shift_expected_cash(
    (select id from public.cash_shifts where client_uuid = 'c6000000-0000-0000-0000-000000000001')),
  100000::bigint, 'EXPECTED: 100000 tanpa penjualan'
);

-- (2) Jual tunai 2 x 10000
select lives_ok(
  $q$ select public.create_sale(
        'c7000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000001',
        'c3000000-0000-0000-0000-000000000001',
        null,
        jsonb_build_array(jsonb_build_object(
          'product_id', 'c5000000-0000-0000-0000-000000000001',
          'unit_id', 'c4000000-0000-0000-0000-000000000001',
          'qty', 2, 'unit_price', 10000, 'discount', 0)),
        '[{"method":"tunai","amount":20000}]'::jsonb,
        (select id from public.cash_shifts where client_uuid = 'c6000000-0000-0000-0000-000000000001'),
        null, null, null) $q$,
  'SALE: tunai 20000'
);

-- (3) Bayar 50000 untuk total 10000 → kas masuk 10000
select lives_ok(
  $q$ select public.create_sale(
        'c7000000-0000-0000-0000-000000000002',
        'c2000000-0000-0000-0000-000000000001',
        'c3000000-0000-0000-0000-000000000001',
        null,
        jsonb_build_array(jsonb_build_object(
          'product_id', 'c5000000-0000-0000-0000-000000000001',
          'unit_id', 'c4000000-0000-0000-0000-000000000001',
          'qty', 1, 'unit_price', 10000, 'discount', 0)),
        '[{"method":"tunai","amount":50000}]'::jsonb,
        (select id from public.cash_shifts where client_uuid = 'c6000000-0000-0000-0000-000000000001'),
        null, null, null) $q$,
  'SALE: bayar lebih, kembalian 40000'
);

-- (4) Expected = 100000 + 20000 + 10000 = 130000
select is(
  public.shift_expected_cash(
    (select id from public.cash_shifts where client_uuid = 'c6000000-0000-0000-0000-000000000001')),
  130000::bigint, 'EXPECTED: 130000 (kembalian dikurangi)'
);

-- (5) Transfer tidak menambah kas
select lives_ok(
  $q$ select public.create_sale(
        'c7000000-0000-0000-0000-000000000003',
        'c2000000-0000-0000-0000-000000000001',
        'c3000000-0000-0000-0000-000000000001',
        null,
        jsonb_build_array(jsonb_build_object(
          'product_id', 'c5000000-0000-0000-0000-000000000001',
          'unit_id', 'c4000000-0000-0000-0000-000000000001',
          'qty', 2, 'unit_price', 10000, 'discount', 0)),
        '[{"method":"transfer","amount":20000}]'::jsonb,
        (select id from public.cash_shifts where client_uuid = 'c6000000-0000-0000-0000-000000000001'),
        null, null, null) $q$,
  'SALE: transfer 20000'
);

select is(
  public.shift_expected_cash(
    (select id from public.cash_shifts where client_uuid = 'c6000000-0000-0000-0000-000000000001')),
  130000::bigint, 'EXPECTED: transfer tidak menambah kas'
);

-- (6) Tutup shift memakai rumus yang sama
select is(
  (public.close_cash_shift(
    (select id from public.cash_shifts where client_uuid = 'c6000000-0000-0000-0000-000000000001'),
    130000, null, 'c8000000-0000-0000-0000-000000000001')
  ->> 'difference')::bigint,
  0::bigint, 'CLOSE: selisih 0 dengan expected 130000'
);

-- (7) Owner tenant B tidak boleh membaca expected shift tenant A
select tests_set_user('c1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.shift_expected_cash(
        (select id from public.cash_shifts limit 1)) $q$,
  'P0001',
  'Shift tidak ditemukan',
  'RLS: tenant lain ditolak (shift tidak terlihat)'
);

-- (8) Shift tidak dikenal ditolak
select throws_ok(
  $q$ select public.shift_expected_cash('c9000000-0000-0000-0000-0000000000ff') $q$,
  'P0001',
  'Shift tidak ditemukan',
  'EXPECTED: shift tidak dikenal ditolak'
);

select * from finish();
rollback;
