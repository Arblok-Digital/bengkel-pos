-- Tes pgTAP T0.2: isolasi tenant (RLS) + has_role + manajemen privilege
-- Jalankan lewat: supabase test db
-- Semua pengujian berjalan sebagai role `authenticated` / `anon`
-- (via SET LOCAL role + SET LOCAL request.jwt.claims), BUKAN sebagai postgres.

begin;
select plan(26);

-- ─── data uji ────────────────────────────────────────────────────────────────
create extension if not exists pgtap with schema extensions;

-- dua user supabase fiktif
insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'authenticated', 'a@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'b@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

-- dua tenant
insert into public.tenants (id, name, business_type)
values
  ('aaaaaaa1-0000-0000-0000-000000000001', 'Bengkel Maju', 'bengkel'),
  ('aaaaaaa1-0000-0000-0000-000000000002', 'Toko Bangunan Sejahtera', 'toko_bangunan');

insert into public.outlets (id, tenant_id, name)
values
  ('bbbbbbb1-0000-0000-0000-000000000001', 'aaaaaaa1-0000-0000-0000-000000000001', 'Outlet A'),
  ('bbbbbbb1-0000-0000-0000-000000000002', 'aaaaaaa1-0000-0000-0000-000000000002', 'Outlet B');

-- ─── helper sesi ─────────────────────────────────────────────────────────────
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

-- memberships: user A = owner tenant 1; user B = kasir tenant 2
-- (di-insert sebagai postgres/superuser karena ini pembenih data uji)
insert into public.memberships (tenant_id, user_id, role)
values
  ('aaaaaaa1-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaa1-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'kasir');

-- ─── 1. sesi sebagai role authenticated, bukan postgres ──────────────────────
select tests_set_user('11111111-1111-1111-1111-111111111111');

select is(
  current_user, 'authenticated', 'sesi uji berjalan sebagai role authenticated'
);

select is(
  count(*)::int, 1, 'user A melihat tepat 1 tenant (miliknya sendiri)'
) from public.tenants;

select is(
  count(*)::int, 1, 'user A melihat tepat 1 outlet (milik tenant A)'
) from public.outlets;

-- ─── 2. user tenant A TIDAK bisa membaca tenant B ────────────────────────────
select is(
  count(*)::int, 0, 'user A tidak bisa membaca tenant B (nama tersembunyi)'
) from public.tenants where id = 'aaaaaaa1-0000-0000-0000-000000000002';

select is(
  count(*)::int, 0, 'user A tidak bisa membaca outlet tenant B'
) from public.outlets where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002';

-- ─── 3. user A tidak bisa insert dengan tenant_id orang lain ─────────────────
select throws_ok(
  $query$
    insert into public.outlets (tenant_id, name)
    values ('aaaaaaa1-0000-0000-0000-000000000002', 'Outlet bajakan')
  $query$,
  '42501',
  'new row violates row-level security policy for table "outlets"',
  'insert dengan tenant_id tenant B oleh user A ditolak'
);

-- ─── 4. user A tidak bisa mengubah tenant B ──────────────────────────────────
with updated as (
  update public.tenants set name = 'dirampas'
  where id = 'aaaaaaa1-0000-0000-0000-000000000002'
  returning name
)
select is(
  count(*)::int, 0, 'update tenant B oleh user A tidak mengubah baris apa pun'
) from updated;

-- ─── 5. user tenant B: kasir lihat tenant-nya sendiri ────────────────────────
select tests_set_user('22222222-2222-2222-2222-222222222222');

select is(
  count(*)::int, 1, 'user B melihat tepat 1 tenant (miliknya sendiri)'
) from public.tenants;

select is(
  count(*)::int, 0, 'user B tidak bisa membaca tenant A'
) from public.tenants where id = 'aaaaaaa1-0000-0000-0000-000000000001';

-- ─── 6. kasir TIDAK boleh membuat memberships (butuh owner/admin) ────────────
select throws_ok(
  $query$
    insert into public.memberships (tenant_id, user_id, role)
    values ('aaaaaaa1-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'owner')
  $query$,
  '42501',
  'new row violates row-level security policy for table "memberships"',
  'kasir tidak bisa membuat memberships baru (with check has_role gagal)'
);

-- ─── 7. has_role ─────────────────────────────────────────────────────────────
select is(
  public.has_role('aaaaaaa1-0000-0000-0000-000000000002', array['owner', 'admin']),
  false,
  'has_role: kasir bukan owner/admin'
);
select is(
  public.has_role('aaaaaaa1-0000-0000-0000-000000000002', array['kasir']),
  true,
  'has_role: kasir adalah kasir'
);

-- user A adalah owner
select tests_set_user('11111111-1111-1111-1111-111111111111');
select is(
  public.has_role('aaaaaaa1-0000-0000-0000-000000000001', array['owner', 'admin']),
  true,
  'has_role: owner tenant A lolos cek owner'
);
select is(
  public.has_role('aaaaaaa1-0000-0000-0000-000000000002', array['owner', 'admin']),
  false,
  'has_role: owner tenant A tidak dicatat sebagai owner tenant B'
);

-- ─── 8. user B tidak bisa update memberships tenant-nya sendiri ──────────────
-- (dengan policy per perintah: UPDATE menyaring 0 baris, bukan melempar error)
select tests_set_user('22222222-2222-2222-2222-222222222222');
with updated as (
  update public.memberships set role = 'owner'
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002'
    and user_id = '22222222-2222-2222-2222-222222222222'
  returning id
)
select is(
  count(*)::int, 0, 'kasir tidak bisa mengubah memberships (0 baris)'
) from updated;

-- verifikasi sebagai postgres bahwa data TIDAK berubah
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002'
      and user_id = '22222222-2222-2222-2222-222222222222'),
  'kasir', 'VERIF: role B dari tenant B tetap kasir'
);

-- ─── 9. privilege fungsi: is_member/has_role hanya untuk authenticated ──────
-- (pemanggilan di sini sebagai authenticated, yang memang miliki EXECUTE)
select is(
  has_function_privilege('authenticated', 'public.is_member(uuid)', 'execute'),
  true,
  'public.is_member(uuid): authenticated punya EXECUTE'
);
select is(
  has_function_privilege('authenticated', 'public.has_role(uuid,text[])', 'execute'),
  true,
  'public.has_role(uuid,text[]): authenticated punya EXECUTE'
);
select is(
  has_function_privilege('anon', 'public.is_member(uuid)', 'execute'),
  false,
  'public.is_member(uuid): anon TIDAK punya EXECUTE'
);
select is(
  has_function_privilege('anon', 'public.has_role(uuid,text[])', 'execute'),
  false,
  'public.has_role(uuid,text[]): anon TIDAK punya EXECUTE'
);

-- ─── 10. role anon: ditolak di semua tabel ───────────────────────────────────
select tests_set_anon();

select is(
  current_user, 'anon', 'sesi uji berjalan sebagai role anon'
);

select throws_ok(
  $query$ select count(*) from public.tenants $query$,
  '42501',
  'permission denied for table tenants',
  'anon tidak bisa membaca tabel tenants'
);

select throws_ok(
  $query$ select count(*) from public.outlets $query$,
  '42501',
  'permission denied for table outlets',
  'anon tidak bisa membaca tabel outlets'
);

select throws_ok(
  $query$ select count(*) from public.memberships $query$,
  '42501',
  'permission denied for table memberships',
  'anon tidak bisa membaca tabel memberships'
);

select throws_ok(
  $query$ insert into public.outlets (tenant_id, name) values ('aaaaaaa1-0000-0000-0000-000000000001', 'Outlet anon') $query$,
  '42501',
  'permission denied for table outlets',
  'anon tidak bisa insert ke tabel outlets'
);

select throws_ok(
  $query$ select public.is_member('aaaaaaa1-0000-0000-0000-000000000001'::uuid) $query$,
  '42501',
  'permission denied for function is_member',
  'anon tidak bisa memanggil is_member langsung'
);

select * from finish();
rollback;
