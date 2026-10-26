-- Tes pgTAP 0006: onboarding tenant (RPC create_tenant)
-- Jalankan lewat: supabase test db
--
-- Cakupan:
--   anon tidak bisa memanggil RPC
--   user login membuat tenant + outlet + membership owner (atomik)
--   idempoten lewat client_uuid (tidak menggandakan tenant/outlet)
--   client_uuid milik user lain ditolak
--   input tidak valid ditolak
--   isolasi tenant tetap berlaku setelah onboarding

begin;
select plan(19);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'ab000000-0000-0000-0000-000000000001', 'authenticated', 'a@onboard.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'ab000000-0000-0000-0000-000000000002', 'authenticated', 'b@onboard.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

create or replace function tests_set_user(p_user uuid) returns void
  language plpgsql as $$
  begin
    execute format('set local "request.jwt.claims" to %L', json_build_object('sub', p_user, 'role', 'authenticated'));
    execute format('set local role %I', 'authenticated');
  end;
  $$;

create or replace function tests_set_anon() returns void
  language plpgsql as $$
  begin
    execute format('set local "request.jwt.claims" to %L', json_build_object('role', 'anon'));
    execute 'set local role anon';
  end;
  $$;

create or replace function tests_set_postgres() returns void
  language plpgsql as $$
  begin
    execute 'reset request.jwt.claims';
    execute 'reset role';
  end;
  $$;

-- (1) anon tidak punya EXECUTE
select tests_set_anon();
select throws_ok(
  $q$ select * from public.create_tenant(
        'ab000000-0000-0000-0000-0000000000c1', 'Bengkel Anon', 'bengkel', 'Outlet Anon') $q$,
  '42501',
  'permission denied for function create_tenant',
  'ANON: tidak bisa memanggil create_tenant'
);

-- (2) user A membuat usaha
select tests_set_user('ab000000-0000-0000-0000-000000000001');
select is(
  (select count(*)::int from public.create_tenant(
     'ab000000-0000-0000-0000-0000000000c1', 'Bengkel A', 'bengkel', 'Outlet Utama')),
  1,
  'A: create_tenant mengembalikan 1 baris'
);

-- (3) panggilan ulang mengembalikan tenant yang sama
select is(
  (select tenant_id from public.create_tenant(
     'ab000000-0000-0000-0000-0000000000c1', 'Bengkel A', 'bengkel', 'Outlet Utama')),
  (select id from public.tenants where client_uuid = 'ab000000-0000-0000-0000-0000000000c1'),
  'A: panggilan ulang mengembalikan tenant yang sama'
);

-- (4) panggilan ulang mengembalikan outlet yang sama
select is(
  (select outlet_id from public.create_tenant(
     'ab000000-0000-0000-0000-0000000000c1', 'Bengkel A', 'bengkel', 'Outlet Utama')),
  (select o.id from public.outlets o
    join public.tenants t on t.id = o.tenant_id
   where t.client_uuid = 'ab000000-0000-0000-0000-0000000000c1'),
  'A: panggilan ulang mengembalikan outlet yang sama'
);

-- (5) tenant tidak berganda
select tests_set_postgres();
select is(
  (select count(*)::int from public.tenants
    where client_uuid = 'ab000000-0000-0000-0000-0000000000c1'),
  1,
  'VERIF: tenant tidak berganda'
);

-- (6) outlet tidak berganda
select is(
  (select count(*)::int from public.outlets o
    join public.tenants t on t.id = o.tenant_id
   where t.client_uuid = 'ab000000-0000-0000-0000-0000000000c1'),
  1,
  'VERIF: outlet tidak berganda'
);

-- (7) membership owner untuk A
select is(
  (select count(*)::int from public.memberships m
    join public.tenants t on t.id = m.tenant_id
   where t.client_uuid = 'ab000000-0000-0000-0000-0000000000c1'
     and m.user_id = 'ab000000-0000-0000-0000-000000000001'
     and m.role = 'owner'),
  1,
  'VERIF: A menjadi owner'
);

-- (8) created_by diisi dari sesi
select is(
  (select created_by from public.tenants
    where client_uuid = 'ab000000-0000-0000-0000-0000000000c1'),
  'ab000000-0000-0000-0000-000000000001'::uuid,
  'VERIF: created_by = user sesi'
);

-- (9) user B memakai client_uuid yang sama ditolak
select tests_set_user('ab000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select * from public.create_tenant(
        'ab000000-0000-0000-0000-0000000000c1', 'Tenant B', 'bengkel', 'Outlet B') $q$,
  'P0001',
  'client_uuid sudah dipakai',
  'B: client_uuid milik user lain ditolak'
);

-- (10) tenant tetap satu
select tests_set_postgres();
select is(
  (select count(*)::int from public.tenants
    where client_uuid = 'ab000000-0000-0000-0000-0000000000c1'),
  1,
  'VERIF: tenant tetap satu setelah percobaan B'
);

-- (11) tipe usaha tidak valid
select tests_set_user('ab000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select * from public.create_tenant(
        'ab000000-0000-0000-0000-0000000000c2', 'Usaha X', 'restoran', 'Outlet X') $q$,
  'P0001',
  'Tipe usaha tidak valid',
  'A: tipe usaha tidak valid ditolak'
);

-- (12) nama usaha kosong
select throws_ok(
  $q$ select * from public.create_tenant(
        'ab000000-0000-0000-0000-0000000000c3', '   ', 'bengkel', 'Outlet X') $q$,
  'P0001',
  'Nama usaha wajib diisi',
  'A: nama usaha kosong ditolak'
);

-- (13) nama outlet kosong
select throws_ok(
  $q$ select * from public.create_tenant(
        'ab000000-0000-0000-0000-0000000000c4', 'Usaha Y', 'bengkel', '') $q$,
  'P0001',
  'Nama outlet wajib diisi',
  'A: nama outlet kosong ditolak'
);

-- (14) client_uuid null
select throws_ok(
  $q$ select * from public.create_tenant(null, 'Usaha Z', 'bengkel', 'Outlet Z') $q$,
  'P0001',
  'client_uuid wajib diisi',
  'A: client_uuid null ditolak'
);

-- (15) A melihat tenant miliknya
select is(
  count(*)::int, 1, 'A: melihat tenant hasil onboarding (1 baris)'
) from public.tenants;

-- (16) A melihat outlet miliknya
select is(
  count(*)::int, 1, 'A: melihat outlet hasil onboarding (1 baris)'
) from public.outlets;

-- (17) B tidak melihat tenant A
select tests_set_user('ab000000-0000-0000-0000-000000000002');
select is(
  count(*)::int, 0, 'B: tidak melihat tenant A (0 baris)'
) from public.tenants;

-- (18) B tidak melihat outlet A
select is(
  count(*)::int, 0, 'B: tidak melihat outlet A (0 baris)'
) from public.outlets;

-- (19) insert tenant langsung tetap ditolak (tanpa policy INSERT)
select tests_set_user('ab000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ insert into public.tenants (name, business_type)
      values ('Tenant Bajakan', 'bengkel') $q$,
  '42501',
  'new row violates row-level security policy for table "tenants"',
  'A: insert tenant langsung ditolak'
);

select * from finish();
rollback;
