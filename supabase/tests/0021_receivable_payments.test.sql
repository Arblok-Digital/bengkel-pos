-- pgTAP: receivable_payments + RPC pay_receivable (0021)
begin;
select plan(11);

create extension if not exists pgtap;

-- ─── Setup ────────────────────────────────────────────────────────────────────
-- Reuse test helpers from 0015
create or replace function tests_set_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end; $$;

create or replace function tests_set_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end; $$;

-- Test users
do $$
declare
  v_owner uuid := 'c1000000-0000-0000-0000-000000000001';
  v_kasir uuid := 'c1000000-0000-0000-0000-000000000002';
  v_tenant uuid := 'c2000000-0000-0000-0000-000000000001';
  v_outlet uuid := 'c3000000-0000-0000-0000-000000000001';
  v_customer uuid := 'c6000000-0000-0000-0000-000000000001';
  v_product uuid := 'c5000000-0000-0000-0000-000000000001';
  v_unit uuid := 'c4000000-0000-0000-0000-000000000001';
  v_shift uuid := 'c7000000-0000-0000-0000-000000000001';
begin
  -- Auth users
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
     'owner-rp@test.test', extensions.crypt('test123', extensions.gen_salt('bf')),
     now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_kasir, 'authenticated', 'authenticated',
     'kasir-rp@test.test', extensions.crypt('test123', extensions.gen_salt('bf')),
     now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

  insert into auth.identities (id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at)
  values
    (gen_random_uuid(), v_owner, jsonb_build_object('sub', v_owner::text), 'email',
     'owner-rp@test.test', now(), now(), now()),
    (gen_random_uuid(), v_kasir, jsonb_build_object('sub', v_kasir::text), 'email',
     'kasir-rp@test.test', now(), now(), now());

  -- Tenant + outlet + memberships
  insert into public.tenants (id, name, business_type, client_uuid, created_by)
  values (v_tenant, 'Toko Test RP', 'toko_bangunan', gen_random_uuid(), v_owner);
  insert into public.outlets (id, tenant_id, name, created_by)
  values (v_outlet, v_tenant, 'Outlet RP', v_owner);
  insert into public.memberships (tenant_id, user_id, role, created_by)
  values
    (v_tenant, v_owner, 'owner', v_owner),
    (v_tenant, v_kasir, 'kasir', v_owner);

  -- Unit + product + stock
  insert into public.units (id, tenant_id, name, created_by)
  values (v_unit, v_tenant, 'pcs', v_owner);
  insert into public.products (id, tenant_id, name, base_unit_id, kind, sell_price, created_by)
  values (v_product, v_tenant, 'Produk RP', v_unit, 'barang', 50000, v_owner);
  insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note, created_by)
  values (v_tenant, v_product, v_outlet, 100, 'adjustment', 'Stok awal', v_owner);

  -- Customer with credit limit
  insert into public.customers (id, tenant_id, name, credit_limit, created_by)
  values (v_customer, v_tenant, 'Pelanggan RP', 500000, v_owner);

  -- Shift
  insert into public.cash_shifts (id, tenant_id, outlet_id, cashier_id, opening_cash, client_uuid, created_by)
  values (v_shift, v_tenant, v_outlet, v_kasir, 100000, 'c7000000-0000-0000-0000-000000000002', v_kasir);
end $$;

-- ─── Buat penjualan kredit via create_sale ────────────────────────────────────
select tests_set_user('c1000000-0000-0000-0000-000000000002'); -- kasir

-- Sale 1: kredit penuh 100.000 (2 x 50.000)
select lives_ok(
  $q$ select public.create_sale(
    'c8000000-0000-0000-0000-000000000001',
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    'c6000000-0000-0000-0000-000000000001',
    '[{"product_id":"c5000000-0000-0000-0000-000000000001","unit_id":"c4000000-0000-0000-0000-000000000001","qty":2,"unit_price":50000,"discount":0}]'::jsonb,
    '[{"method":"kredit_tempo","amount":100000}]'::jsonb,
    'c7000000-0000-0000-0000-000000000001', null, null, null) $q$,
  'Penjualan kredit 100.000 berhasil'
);

-- (1) Verifikasi receivable tercipta
select tests_set_postgres();
select is(
  (select count(*)::int from public.receivables
   where tenant_id = 'c2000000-0000-0000-0000-000000000001'
     and status = 'open'),
  1, 'VERIF: 1 piutang open tercipta'
);

select is(
  (select amount from public.receivables
   where tenant_id = 'c2000000-0000-0000-0000-000000000001'
     and status = 'open'),
  100000::bigint, 'VERIF: piutang = 100.000'
);

-- ─── (3) Cicilan 1: bayar 40.000 ─────────────────────────────────────────────
select tests_set_user('c1000000-0000-0000-0000-000000000001'); -- owner
select lives_ok(
  $q$ select public.pay_receivable(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.receivables
     where tenant_id = 'c2000000-0000-0000-0000-000000000001' limit 1),
    40000, 'tunai', null) $q$,
  'Cicilan 1: bayar 40.000 berhasil'
);

-- (4) Verifikasi status partial
select tests_set_postgres();
select is(
  (select status from public.receivables
   where tenant_id = 'c2000000-0000-0000-0000-000000000001'),
  'partial', 'VERIF: status piutang = partial'
);

-- (5) Verifikasi sisa = 60.000
select is(
  (select (r.amount - coalesce(sum(rp.amount), 0))::bigint
   from public.receivables r
   left join public.receivable_payments rp on rp.receivable_id = r.id
   where r.tenant_id = 'c2000000-0000-0000-0000-000000000001'
   group by r.id),
  60000::bigint, 'VERIF: sisa piutang = 60.000'
);

-- ─── (6) Cicilan 2: bayar 60.000 (lunas) ─────────────────────────────────────
select tests_set_user('c1000000-0000-0000-0000-000000000001');
select lives_ok(
  $q$ select public.pay_receivable(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.receivables
     where tenant_id = 'c2000000-0000-0000-0000-000000000001' limit 1),
    60000, 'transfer', 'TRF-001') $q$,
  'Cicilan 2: bayar 60.000 berhasil (lunas)'
);

-- (7) Verifikasi status paid
select tests_set_postgres();
select is(
  (select status from public.receivables
   where tenant_id = 'c2000000-0000-0000-0000-000000000001'),
  'paid', 'VERIF: status piutang = paid (lunas)'
);

-- (8) Bayar lagi harus ditolak (sudah lunas)
select tests_set_user('c1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.pay_receivable(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.receivables
     where tenant_id = 'c2000000-0000-0000-0000-000000000001' limit 1),
    1000, 'tunai', null) $q$,
  'P0001',
  'Piutang sudah lunas',
  'REJECT: bayar piutang yang sudah lunas ditolak'
);

-- (9) Pembayaran melebihi sisa harus ditolak (reset dulu untuk tes baru)
-- Buat sale baru
select tests_set_user('c1000000-0000-0000-0000-000000000002');
select lives_ok(
  $q$ select public.create_sale(
    'c8000000-0000-0000-0000-000000000002',
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    'c6000000-0000-0000-0000-000000000001',
    '[{"product_id":"c5000000-0000-0000-0000-000000000001","unit_id":"c4000000-0000-0000-0000-000000000001","qty":1,"unit_price":50000,"discount":0}]'::jsonb,
    '[{"method":"kredit_tempo","amount":50000}]'::jsonb,
    'c7000000-0000-0000-0000-000000000001', null, null, null) $q$,
  'Penjualan kredit 50.000 (untuk tes overcharge)'
);

select tests_set_user('c1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.pay_receivable(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.receivables
     where tenant_id = 'c2000000-0000-0000-0000-000000000001'
       and status = 'open' limit 1),
    99999, 'tunai', null) $q$,
  'P0001',
  'Nominal pembayaran (99999) melebihi sisa piutang (50000)',
  'REJECT: pembayaran melebihi sisa piutang ditolak'
);

select * from finish();
rollback;
