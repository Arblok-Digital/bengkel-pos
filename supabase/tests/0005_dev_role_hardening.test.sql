-- Tes pgTAP 0005: hardening role dev
-- Jalankan lewat: supabase test db
--
-- Cakupan:
--   owner/admin TIDAK bisa memberi role dev (INSERT maupun UPDATE)
--   owner TIDAK bisa mengubah/menghapus baris milik dev
--   dev yang sudah ada BISA membuat dev baru (kontrol positif)
--   dev nonaktif kehilangan akses global

begin;
select plan(17);

create extension if not exists pgtap with schema extensions;

-- ─── data uji ────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'de000000-0000-0000-0000-000000000010', 'authenticated', 'dev@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'de000000-0000-0000-0000-000000000011', 'authenticated', 'owner@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'de000000-0000-0000-0000-000000000012', 'authenticated', 'admin@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'de000000-0000-0000-0000-000000000013', 'authenticated', 'kasir@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'de000000-0000-0000-0000-000000000014', 'authenticated', 'x@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('de000000-0000-0000-0000-0000000000b1', 'Tenant Satu', 'bengkel'),
  ('de000000-0000-0000-0000-0000000000b2', 'Tenant Dua', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('de000000-0000-0000-0000-0000000000b1', 'de000000-0000-0000-0000-000000000010', 'dev'),
  ('de000000-0000-0000-0000-0000000000b1', 'de000000-0000-0000-0000-000000000011', 'owner'),
  ('de000000-0000-0000-0000-0000000000b1', 'de000000-0000-0000-0000-000000000012', 'admin'),
  ('de000000-0000-0000-0000-0000000000b1', 'de000000-0000-0000-0000-000000000013', 'kasir');

-- ─── helper sesi ─────────────────────────────────────────────────────────────
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
-- A. Owner/admin tidak boleh memberi role dev
-- ══════════════════════════════════════════════════════════════════════════

-- (1) owner insert membership dev untuk user X
select tests_set_user('de000000-0000-0000-0000-000000000011');
select throws_ok(
  $q$ insert into public.memberships (tenant_id, user_id, role)
      values ('de000000-0000-0000-0000-0000000000b1',
              'de000000-0000-0000-0000-000000000014', 'dev') $q$,
  '42501',
  'new row violates row-level security policy for table "memberships"',
  'OWNER: memberi role dev ditolak'
);

-- (2) verifikasi tidak ada baris X
select tests_set_postgres();
select is(
  count(*)::int, 0, 'VERIF: membership X tidak dibuat'
) from public.memberships
where user_id = 'de000000-0000-0000-0000-000000000014';

-- (3) owner tidak bisa menaikkan kasir menjadi dev
select tests_set_user('de000000-0000-0000-0000-000000000011');
select throws_ok(
  $q$ update public.memberships set role = 'dev'
      where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
        and user_id = 'de000000-0000-0000-0000-000000000013' $q$,
  '42501',
  'new row violates row-level security policy for table "memberships"',
  'OWNER: menaikkan kasir menjadi dev ditolak'
);

-- (4) verifikasi kasir tetap kasir
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
      and user_id = 'de000000-0000-0000-0000-000000000013'),
  'kasir', 'VERIF: kasir tetap kasir'
);

-- (5) admin juga tidak bisa menaikkan kasir menjadi dev
select tests_set_user('de000000-0000-0000-0000-000000000012');
select throws_ok(
  $q$ update public.memberships set role = 'dev'
      where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
        and user_id = 'de000000-0000-0000-0000-000000000013' $q$,
  '42501',
  'new row violates row-level security policy for table "memberships"',
  'ADMIN: menaikkan kasir menjadi dev ditolak'
);

-- (6) verifikasi kasir tetap kasir
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
      and user_id = 'de000000-0000-0000-0000-000000000013'),
  'kasir', 'VERIF: kasir tetap kasir setelah percobaan admin'
);

-- (7) owner tidak bisa mengubah baris milik dev (0 baris)
select tests_set_user('de000000-0000-0000-0000-000000000011');
with updated as (
  update public.memberships set role = 'kasir'
  where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
    and user_id = 'de000000-0000-0000-0000-000000000010'
  returning id
)
select is(
  count(*)::int, 0, 'OWNER: tidak bisa mengubah baris dev (0 baris)'
) from updated;

-- (8) verifikasi role dev tetap
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
      and user_id = 'de000000-0000-0000-0000-000000000010'),
  'dev', 'VERIF: role dev tidak berubah'
);

-- (9) owner tidak bisa menghapus baris milik dev (0 baris)
select tests_set_user('de000000-0000-0000-0000-000000000011');
with deleted as (
  delete from public.memberships
  where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
    and user_id = 'de000000-0000-0000-0000-000000000010'
  returning id
)
select is(
  count(*)::int, 0, 'OWNER: tidak bisa menghapus baris dev (0 baris)'
) from deleted;

-- (10) verifikasi membership dev masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: membership dev masih ada'
) from public.memberships
where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
  and user_id = 'de000000-0000-0000-0000-000000000010';

-- ══════════════════════════════════════════════════════════════════════════
-- B. Dev yang sudah ada boleh membuat dev baru (kontrol positif)
-- ══════════════════════════════════════════════════════════════════════════

-- (11) dev insert role dev untuk X
select tests_set_user('de000000-0000-0000-0000-000000000010');
with inserted as (
  insert into public.memberships (tenant_id, user_id, role)
  values ('de000000-0000-0000-0000-0000000000b1',
          'de000000-0000-0000-0000-000000000014', 'dev')
  returning id
)
select is(
  count(*)::int, 1, 'DEV: membuat dev baru (1 baris)'
) from inserted;

-- (12) verifikasi X sekarang dev
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
      and user_id = 'de000000-0000-0000-0000-000000000014'),
  'dev', 'VERIF: X tercatat sebagai dev'
);

-- (13) X yang baru jadi dev bisa melihat semua tenant
select tests_set_user('de000000-0000-0000-0000-000000000014');
select is(
  count(*)::int, 2, 'DEV BARU: melihat semua tenant (2 baris)'
) from public.tenants
where id in ('de000000-0000-0000-0000-0000000000b1',
             'de000000-0000-0000-0000-0000000000b2');

-- ══════════════════════════════════════════════════════════════════════════
-- C. Dev nonaktif kehilangan akses global
-- ══════════════════════════════════════════════════════════════════════════

-- (14) nonaktifkan dev (postgres)
select tests_set_postgres();
with updated as (
  update public.memberships set active = false
  where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
    and user_id = 'de000000-0000-0000-0000-000000000010'
  returning id
)
select is(
  count(*)::int, 1, 'CTL: dev dinonaktifkan (1 baris)'
) from updated;

-- (15) dev nonaktif tidak melihat tenant apa pun
select tests_set_user('de000000-0000-0000-0000-000000000010');
select is(
  count(*)::int, 0, 'DEV NONAKTIF: tidak melihat tenant (0 baris)'
) from public.tenants;

-- (16) aktifkan kembali (postgres)
select tests_set_postgres();
with updated as (
  update public.memberships set active = true
  where tenant_id = 'de000000-0000-0000-0000-0000000000b1'
    and user_id = 'de000000-0000-0000-0000-000000000010'
  returning id
)
select is(
  count(*)::int, 1, 'CTL: dev diaktifkan kembali (1 baris)'
) from updated;

-- (17) dev aktif kembali melihat semua tenant
select tests_set_user('de000000-0000-0000-0000-000000000010');
select is(
  count(*)::int, 2, 'DEV AKTIF: kembali melihat semua tenant (2 baris)'
) from public.tenants
where id in ('de000000-0000-0000-0000-0000000000b1',
             'de000000-0000-0000-0000-0000000000b2');

select * from finish();
rollback;
