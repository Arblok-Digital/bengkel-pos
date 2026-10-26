-- Tes pgTAP 0016: tutup shift menghitung kas masuk dari penjualan
begin;
select plan(11);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'a8000000-0000-0000-0000-000000000001', 'authenticated', 'owner.shiftcash@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a8000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.shiftcash@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type)
values ('a9000000-0000-0000-0000-000000000001', 'Tenant Shift Cash', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('a9000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001', 'owner'),
  ('a9000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000002', 'kasir');

insert into public.outlets (id, tenant_id, name)
values ('aa000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000001', 'Outlet Kas');

insert into public.units (id, tenant_id, name)
values ('ab000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000001', 'pcs');

insert into public.products (id, tenant_id, name, base_unit_id, kind, track_stock, sell_price, cost_price)
values ('ac000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000001',
        'Barang Kas', 'ab000000-0000-0000-0000-000000000001', 'barang', true, 10000, 6000);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note)
values ('a9000000-0000-0000-0000-000000000001',
        'ac000000-0000-0000-0000-000000000001',
        'aa000000-0000-0000-0000-000000000001', 100, 'adjustment', 'Stok awal');

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

-- (1) Kasir buka shift modal 100000
select tests_set_user('a8000000-0000-0000-0000-000000000002');
select is(
  (public.open_cash_shift(
    'a9000000-0000-0000-0000-000000000001',
    'aa000000-0000-0000-0000-000000000001',
    100000, 'ad000000-0000-0000-0000-000000000001')) is not null,
  true, 'KASIR: buka shift 100000'
);

-- (2) Penjualan tunai 2 pcs = 20000 pada shift itu
select lives_ok(
  $q$ select public.create_sale(
        'ae000000-0000-0000-0000-000000000001',
        'a9000000-0000-0000-0000-000000000001',
        'aa000000-0000-0000-0000-000000000001',
        null,
        jsonb_build_array(jsonb_build_object(
          'product_id', 'ac000000-0000-0000-0000-000000000001',
          'unit_id', 'ab000000-0000-0000-0000-000000000001',
          'qty', 2, 'unit_price', 10000, 'discount', 0)),
        '[{"method":"tunai","amount":20000}]'::jsonb,
        (select id from public.cash_shifts
          where client_uuid = 'ad000000-0000-0000-0000-000000000001'),
        null, null, null) $q$,
  'SALE: penjualan tunai 20000 pada shift'
);

-- (3) Penjualan tunai bayar 50000 (kembalian 30000) → kas masuk 20000
select lives_ok(
  $q$ select public.create_sale(
        'ae000000-0000-0000-0000-000000000002',
        'a9000000-0000-0000-0000-000000000001',
        'aa000000-0000-0000-0000-000000000001',
        null,
        jsonb_build_array(jsonb_build_object(
          'product_id', 'ac000000-0000-0000-0000-000000000001',
          'unit_id', 'ab000000-0000-0000-0000-000000000001',
          'qty', 2, 'unit_price', 10000, 'discount', 0)),
        '[{"method":"tunai","amount":50000}]'::jsonb,
        (select id from public.cash_shifts
          where client_uuid = 'ad000000-0000-0000-0000-000000000001'),
        null, null, null) $q$,
  'SALE: penjualan bayar lebih, kembalian 30000'
);

-- (4) Penjualan transfer tidak menambah kas fisik
select lives_ok(
  $q$ select public.create_sale(
        'ae000000-0000-0000-0000-000000000003',
        'a9000000-0000-0000-0000-000000000001',
        'aa000000-0000-0000-0000-000000000001',
        null,
        jsonb_build_array(jsonb_build_object(
          'product_id', 'ac000000-0000-0000-0000-000000000001',
          'unit_id', 'ab000000-0000-0000-0000-000000000001',
          'qty', 2, 'unit_price', 10000, 'discount', 0)),
        '[{"method":"transfer","amount":20000}]'::jsonb,
        (select id from public.cash_shifts
          where client_uuid = 'ad000000-0000-0000-0000-000000000001'),
        null, null, null) $q$,
  'SALE: penjualan transfer 20000'
);

-- (5) Tutup shift: expected = 100000 + (20000 + 20000) = 140000
select is(
  (public.close_cash_shift(
    (select id from public.cash_shifts
      where client_uuid = 'ad000000-0000-0000-0000-000000000001'),
    140000, 'Tutup kas', 'af000000-0000-0000-0000-000000000001')
  ->> 'expected_cash')::bigint,
  140000::bigint, 'SHIFT: expected 140000 (tunai saja, transfer diabaikan)'
);

-- (6) Selisih 0
select is(
  (select difference from public.cash_shifts
    where client_uuid = 'ad000000-0000-0000-0000-000000000001'),
  0::bigint, 'SHIFT: selisih 0'
);

-- (7) Shift kedua tanpa penjualan → expected 0
select is(
  (public.open_cash_shift(
    'a9000000-0000-0000-0000-000000000001',
    'aa000000-0000-0000-0000-000000000001',
    0, 'ad000000-0000-0000-0000-000000000002')) is not null,
  true, 'KASIR: buka shift kedua modal 0'
);

select is(
  (public.close_cash_shift(
    (select id from public.cash_shifts
      where client_uuid = 'ad000000-0000-0000-0000-000000000002'),
    0, null, 'af000000-0000-0000-0000-000000000002')
  ->> 'expected_cash')::bigint,
  0::bigint, 'SHIFT: shift kedua expected 0 (tanpa penjualan)'
);

-- (8) Penjualan yang di-void tidak dihitung
select is(
  (public.open_cash_shift(
    'a9000000-0000-0000-0000-000000000001',
    'aa000000-0000-0000-0000-000000000001',
    50000, 'ad000000-0000-0000-0000-000000000003')) is not null,
  true, 'KASIR: buka shift ketiga modal 50000'
);

select lives_ok(
  $q$ select public.create_sale(
        'ae000000-0000-0000-0000-000000000004',
        'a9000000-0000-0000-0000-000000000001',
        'aa000000-0000-0000-0000-000000000001',
        null,
        jsonb_build_array(jsonb_build_object(
          'product_id', 'ac000000-0000-0000-0000-000000000001',
          'unit_id', 'ab000000-0000-0000-0000-000000000001',
          'qty', 1, 'unit_price', 10000, 'discount', 0)),
        '[{"method":"tunai","amount":10000}]'::jsonb,
        (select id from public.cash_shifts
          where client_uuid = 'ad000000-0000-0000-0000-000000000003'),
        null, null, null) $q$,
  'SALE: penjualan pada shift ketiga'
);

select tests_set_postgres();
update public.sales set status = 'void'
where client_uuid = 'ae000000-0000-0000-0000-000000000004';

select tests_set_user('a8000000-0000-0000-0000-000000000002');
select is(
  (public.close_cash_shift(
    (select id from public.cash_shifts
      where client_uuid = 'ad000000-0000-0000-0000-000000000003'),
    50000, null, 'af000000-0000-0000-0000-000000000003')
  ->> 'expected_cash')::bigint,
  50000::bigint, 'SHIFT: penjualan void tidak menambah kas'
);

select * from finish();
rollback;
