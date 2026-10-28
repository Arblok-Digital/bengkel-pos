-- Tes pgTAP 0024: payables + payable_payments (T6.3)
-- Hutang supplier + pembayaran. Tulis hanya via RPC security definer.
begin;
select plan(18);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000041', 'authenticated', 'owner.pay@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000042', 'authenticated', 'kasir.pay@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000043', 'authenticated', 'admin.pay@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000044', 'authenticated', 'owner2.pay@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('f2000000-0000-0000-0000-000000000041', 'Tenant Pay A', 'toko_bangunan'),
  ('f2000000-0000-0000-0000-000000000042', 'Tenant Pay B', 'toko_bangunan');

insert into public.outlets (id, tenant_id, name) values
  ('f3000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'Gudang A'),
  ('f3000000-0000-0000-0000-000000000042', 'f2000000-0000-0000-0000-000000000042', 'Gudang B');

insert into public.memberships (tenant_id, user_id, role) values
  ('f2000000-0000-0000-0000-000000000041', 'f1000000-0000-0000-0000-000000000041', 'owner'),
  ('f2000000-0000-0000-0000-000000000041', 'f1000000-0000-0000-0000-000000000042', 'kasir'),
  ('f2000000-0000-0000-0000-000000000041', 'f1000000-0000-0000-0000-000000000043', 'admin'),
  ('f2000000-0000-0000-0000-000000000042', 'f1000000-0000-0000-0000-000000000044', 'owner');

insert into public.suppliers (id, tenant_id, name, phone, payment_terms_days) values
  ('f4000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'Supplier A', '0821', 14),
  ('f4000000-0000-0000-0000-000000000042', 'f2000000-0000-0000-0000-000000000042', 'Supplier B', '0822', 0);

insert into public.purchase_orders (id, tenant_id, outlet_id, po_no, client_uuid, supplier_id, status, total)
values
  ('f5000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'f3000000-0000-0000-0000-000000000041', 'PO-001', '00000000-0000-0000-0000-000000000001'::uuid, 'f4000000-0000-0000-0000-000000000041', 'ordered', 1000000);

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

-- ═══════════════════════════════════════════════════════════════════════════
-- KASIR: baca boleh, buat/bayar hutang ditolak
-- ═══════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000042');

select is(count(*)::int, 0, 'KASIR: melihat 0 payable') from public.payables;

select throws_ok(
  $q$ select public.pay_payable(
    'f2000000-0000-0000-0000-000000000041'::uuid,
    'f5000000-0000-0000-0000-000000000041'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    500000::bigint,
    'tunai',
    null
  ) $q$,
  '42501',
  'Hanya owner/admin yang boleh membayar hutang',
  'KASIR: bayar hutang via RPC ditolak'
);

select tests_set_postgres();
select is(count(*)::int, 0, 'VERIF: payable tetap 0') from public.payables;

-- ═══════════════════════════════════════════════════════════════════════════
-- OWNER: buat hutang, bayar (open → partial → paid), idempoten
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000041');

with created as (
  select public.create_payable(
    '00000000-0000-0000-0000-000000000003'::uuid,
    'f2000000-0000-0000-0000-000000000041'::uuid,
    'f3000000-0000-0000-0000-000000000041'::uuid,
    'f4000000-0000-0000-0000-000000000041'::uuid,
    'f5000000-0000-0000-0000-000000000041'::uuid,
    1000000::bigint,
    (current_date + interval '14 days')::date,
    'Hutang PO-001'
  ) as result
)
select is((result ->> 'idempotent')::boolean, false, 'OWNER: buat payable (idempotent false)') from created;

select tests_set_postgres();
select is(
  (select amount from public.payables where client_uuid = '00000000-0000-0000-0000-000000000003'::uuid),
  1000000::bigint, 'VERIF: payable amount = 1.000.000'
);
select is(
  (select status from public.payables where client_uuid = '00000000-0000-0000-0000-000000000003'::uuid),
  'open', 'VERIF: status payable = open'
);

-- Bayar pertama: 500.000 → status partial.
select tests_set_user('f1000000-0000-0000-0000-000000000041');
with paid1 as (
  select public.pay_payable(
    'f2000000-0000-0000-0000-000000000041'::uuid,
    (select id from public.payables where client_uuid = '00000000-0000-0000-0000-000000000003'::uuid),
    '00000000-0000-0000-0000-000000000004'::uuid,
    500000::bigint,
    'tunai',
    'TRF-001'
  ) as result
)
select is((paid1.result ->> 'status'), 'partial', 'OWNER: bayar 500.000 -> status partial') from paid1;

select tests_set_postgres();
select is(
  (select total_paid from public.payables where client_uuid = '00000000-0000-0000-0000-000000000003'::uuid),
  500000::bigint, 'VERIF: total_paid = 500.000'
);
select is(
  count(*)::int, 1, 'VERIF: 1 pembayaran payable'
) from public.payable_payments;

-- Bayar kedua: 500.000 → status paid (lunas).
select tests_set_user('f1000000-0000-0000-0000-000000000041');
with paid2 as (
  select public.pay_payable(
    'f2000000-0000-0000-0000-000000000041'::uuid,
    (select id from public.payables where client_uuid = '00000000-0000-0000-0000-000000000003'::uuid),
    '00000000-0000-0000-0000-000000000005'::uuid,
    500000::bigint,
    'transfer',
    'TRF-002'
  ) as result
)
select is((paid2.result ->> 'status'), 'paid', 'OWNER: bayar 500.000 lagi -> status paid') from paid2;

select tests_set_postgres();
select is(
  (select total_paid from public.payables where client_uuid = '00000000-0000-0000-0000-000000000003'::uuid),
  1000000::bigint, 'VERIF: total_paid = 1.000.000 (lunas)'
);
select is(
  (select status from public.payables where client_uuid = '00000000-0000-0000-0000-000000000003'::uuid),
  'paid', 'VERIF: status payable = paid'
);

-- Idempotensi: client_uuid pembayaran sama → idempotent true, tidak duplikat.
select tests_set_user('f1000000-0000-0000-0000-000000000041');
with idem as (
  select public.pay_payable(
    'f2000000-0000-0000-0000-000000000041'::uuid,
    (select id from public.payables where client_uuid = '00000000-0000-0000-0000-000000000003'::uuid),
    '00000000-0000-0000-0000-000000000005'::uuid,
    500000::bigint,
    'transfer',
    'TRF-002'
  ) as result
)
select is((idem.result ->> 'idempotent')::boolean, true, 'OWNER: client_uuid pembayaran sama -> idempotent true') from idem;

select tests_set_postgres();
select is(
  count(*)::int, 2, 'VERIF: pembayaran tetap 2 baris (tidak duplikat)'
) from public.payable_payments;

-- ═══════════════════════════════════════════════════════════════════════════
-- ISOLASI: owner A tidak boleh bayar payable tenant B via RPC
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000041');
select throws_ok(
  $q$ select public.pay_payable(
    'f2000000-0000-0000-0000-000000000042'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    '00000000-0000-0000-0000-000000000006'::uuid,
    100000::bigint,
    'tunai',
    null
  ) $q$,
  '42501',
  'Hanya owner/admin yang boleh membayar hutang',
  'OWNER A: bayar payable tenant B via RPC ditolak'
);

select is(
  count(*)::int, 0, 'OWNER A: tidak melihat payable tenant B'
) from public.payables where tenant_id = 'f2000000-0000-0000-0000-000000000042';

-- ═══════════════════════════════════════════════════════════════════════════
-- CHECK: nominal tidak valid ditolak
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000041');
select throws_ok(
  $q$ select public.pay_payable(
    'f2000000-0000-0000-0000-000000000041'::uuid,
    (select id from public.payables where client_uuid = '00000000-0000-0000-0000-000000000003'::uuid),
    '00000000-0000-0000-0000-000000000007'::uuid,
    0::bigint,
    'tunai',
    null
  ) $q$,
  'P0001',
  'Nominal pembayaran harus lebih dari 0',
  'OWNER A: pembayaran 0 ditolak'
);

select tests_set_postgres();
select is(
  count(*)::int, 2, 'VERIF: pembayaran tetap 2 baris (pembayaran 0 ditolak)'
) from public.payable_payments;

select * from finish();
rollback;
