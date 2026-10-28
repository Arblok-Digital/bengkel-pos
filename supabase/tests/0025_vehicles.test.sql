-- Tes pgTAP 0025: kendaraan (T7.1)
-- Tulis tabel langsung via SQL (bukan RPC) untuk mencakup policy INSERT/UPDATE/DELETE.
begin;
select plan(14);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000051', 'authenticated', 'owner.vh@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000052', 'authenticated', 'kasir.vh@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000053', 'authenticated', 'admin.vh@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000054', 'authenticated', 'owner2.vh@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('f2000000-0000-0000-0000-000000000051', 'Tenant VH A', 'bengkel'),
  ('f2000000-0000-0000-0000-000000000052', 'Tenant VH B', 'bengkel');

insert into public.outlets (id, tenant_id, name) values
  ('f3000000-0000-0000-0000-000000000051', 'f2000000-0000-0000-0000-000000000051', 'Bengkap A'),
  ('f3000000-0000-0000-0000-000000000052', 'f2000000-0000-0000-0000-000000000052', 'Bengkap B');

insert into public.memberships (tenant_id, user_id, role) values
  ('f2000000-0000-0000-0000-000000000051', 'f1000000-0000-0000-0000-000000000051', 'owner'),
  ('f2000000-0000-0000-0000-000000000051', 'f1000000-0000-0000-0000-000000000052', 'kasir'),
  ('f2000000-0000-0000-0000-000000000051', 'f1000000-0000-0000-0000-000000000053', 'admin'),
  ('f2000000-0000-0000-0000-000000000052', 'f1000000-0000-0000-0000-000000000054', 'owner');

insert into public.customers (id, tenant_id, name, phone, active) values
  ('f6000000-0000-0000-0000-000000000051', 'f2000000-0000-0000-0000-000000000051', 'Budi Santoso', '0821', true),
  ('f6000000-0000-0000-0000-000000000052', 'f2000000-0000-0000-0000-000000000052', 'Siti Rahayu', '0822', true);

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
-- KASIR: baca boleh, tulis ditolak
-- ═══════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000052');

select is(count(*)::int, 0, 'KASIR: melihat 0 kendaraan') from public.vehicles;

select throws_ok(
  $q$ insert into public.vehicles (tenant_id, customer_id, plate_no, brand, model, year)
      values ('f2000000-0000-0000-0000-000000000051', 'f6000000-0000-0000-0000-000000000051', 'B 1234 ABC', 'Toyota', 'Avanza', 2018) $q$,
  '42501',
  'new row violates row-level security policy for table "vehicles"',
  'KASIR: insert kendaraan ditolak'
);

select tests_set_postgres();
select is(count(*)::int, 0, 'VERIF: kendaraan tetap 0') from public.vehicles;

-- ═══════════════════════════════════════════════════════════════════════════
-- OWNER: CRUD kendaraan, plat unik per tenant
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000051');

with inserted as (
  insert into public.vehicles (tenant_id, customer_id, plate_no, brand, model, year, last_odometer)
  values ('f2000000-0000-0000-0000-000000000051', 'f6000000-0000-0000-0000-000000000051', 'B 1234 ABC', 'Toyota', 'Avanza', 2018, 45000)
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert kendaraan (1 baris)') from inserted;

select throws_ok(
  $q$ insert into public.vehicles (tenant_id, customer_id, plate_no, brand, model, year)
      values ('f2000000-0000-0000-0000-000000000051', 'f6000000-0000-0000-0000-000000000051', 'b 1234 abc', 'Honda', 'Brio', 2020) $q$,
  '23505'
);

select tests_set_postgres();
select is(count(*)::int, 1, 'VERIF: kendaraan tetap 1 baris') from public.vehicles;

-- Update merk via owner.
with updated as (
  update public.vehicles
  set brand = 'Honda'
  where tenant_id = 'f2000000-0000-0000-0000-000000000051'
    and plate_no = 'B 1234 ABC'
  returning id
)
select is(count(*)::int, 1, 'OWNER: update kendaraan (1 baris)') from updated;

select tests_set_postgres();
select is(
  (select brand from public.vehicles where plate_no = 'B 1234 ABC'),
  'Honda', 'VERIF: merk kendaraan = Honda'
);

-- Kasir coba update (tidak boleh; RLS USING false). Verifikasi merk tetap.
select tests_set_user('f1000000-0000-0000-0000-000000000052');
update public.vehicles
set brand = 'Suzuki'
where tenant_id = 'f2000000-0000-0000-0000-000000000051'
  and plate_no = 'B 1234 ABC';

select tests_set_postgres();
select is(
  (select brand from public.vehicles where plate_no = 'B 1234 ABC'),
  'Honda', 'VERIF: merk tetap Honda (kasir tidak mengubah)'
);

-- Owner hapus kendaraan.
select tests_set_user('f1000000-0000-0000-0000-000000000051');
with deleted as (
  delete from public.vehicles
  where tenant_id = 'f2000000-0000-0000-0000-000000000051'
    and plate_no = 'B 1234 ABC'
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete kendaraan (1 baris)') from deleted;

select tests_set_postgres();
select is(count(*)::int, 0, 'VERIF: kendaraan terhapus') from public.vehicles;

-- ═══════════════════════════════════════════════════════════════════════════
-- ISOLASI: owner tenant A tidak boleh tulis data tenant B
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000051');
select is(
  count(*)::int, 0, 'OWNER A: tidak melihat kendaraan tenant B'
) from public.vehicles where tenant_id = 'f2000000-0000-0000-0000-000000000052';

select throws_ok(
  $q$ insert into public.vehicles (tenant_id, customer_id, plate_no, brand, model, year)
      values ('f2000000-0000-0000-0000-000000000052', 'f6000000-0000-0000-0000-000000000052', 'B 9999 ZZZ', 'Honda', 'Brio', 2020) $q$,
  '42501',
  'new row violates row-level security policy for table "vehicles"',
  'OWNER A: insert kendaraan tenant B ditolak'
);

select tests_set_postgres();
select is(
  count(*)::int, 0, 'VERIF: tidak ada kendaraan tenant B'
) from public.vehicles where tenant_id = 'f2000000-0000-0000-0000-000000000052';

select * from finish();
rollback;
