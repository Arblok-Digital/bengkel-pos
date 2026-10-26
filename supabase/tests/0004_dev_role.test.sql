-- Tes pgTAP 0004: role dev dengan akses penuh ke semua tenant
-- Jalankan lewat: supabase test db
--
-- Cakupan:
--   dev   : SELECT semua tenant/outlet/membership (termasukan tenant non-miliknya)
--   dev   : INSERT/UPDATE/DELETE outlet di tenant manapun
--   dev   : INSERT/UPDATE/DELETE membership di tenant manapun
--   kasir : tidak bisa melihat/tulis tenant & outlet di luar tenant miliknya
--   verifikasi: setiap tes negatif DIKUATKAN via postgres (data tak berubah)

begin;
select plan(21);

-- ─── data uji ────────────────────────────────────────────────────────────────
create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-1111-1111-1111-111111111111', 'authenticated', 'd@dev.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),  -- D: dev tenant 1
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-2222-2222-2222-222222222222', 'authenticated', 'a@owner.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),  -- A: owner tenant 1
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-3333-3333-3333-333333333333', 'authenticated', 'k@kasir.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());  -- K: kasir tenant 1

insert into public.tenants (id, name, business_type) values
  ('11111111-1111-1111-1111-111111111111', 'Tenant Satu', 'bengkel'),
  ('22222222-2222-2222-2222-222222222222', 'Tenant Dua', 'toko_bangunan');

insert into public.outlets (id, tenant_id, name) values
  ('33333333-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Outlet Satu'),
  ('44444444-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Outlet Dua');

insert into public.memberships (tenant_id, user_id, role) values
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-1111-1111-1111-111111111111', 'dev'),
  ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-2222-2222-2222-222222222222', 'owner'),
  ('11111111-1111-1111-1111-111111111111', 'cccccccc-3333-3333-3333-333333333333', 'kasir');

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

-- ═════════════════════════════════════════════════════════════════════════════
-- BAGIAN 1: DEV dapat melihat semua tenant dan outlet (termasuk non-miliknya)
-- ═════════════════════════════════════════════════════════════════════════════
select tests_set_user('aaaaaaaa-1111-1111-1111-111111111111');

-- (1) dev melihat semua tenant (2 baris, termasuk tenant Dua)
select is(
  count(*)::int, 2,
  'DEV: melihat semua tenant (termasuk non-miliknya)'
) from public.tenants
where id in ('11111111-1111-1111-1111-111111111111',
             '22222222-2222-2222-2222-222222222222');

-- (2) dev melihat semua outlet (2 baris, termasuk outlet tenant Dua)
select is(
  count(*)::int, 2,
  'DEV: melihat semua outlet (termasuk non-miliknya)'
) from public.outlets
where tenant_id in ('11111111-1111-1111-1111-111111111111',
                    '22222222-2222-2222-2222-222222222222');

-- (3) dev melihat semua membership (3 baris)
select is(
  count(*)::int, 3,
  'DEV: melihat semua membership (termasuk non-miliknya)'
) from public.memberships
where tenant_id in ('11111111-1111-1111-1111-111111111111',
                    '22222222-2222-2222-2222-222222222222');
-- ═════════════════════════════════════════════════════════════════════════════
-- BAGIAN 2: DEV dapat menulis (INSERT/UPDATE/DELETE) outlet di tenant lain
-- ═════════════════════════════════════════════════════════════════════════════
-- (4) dev insert outlet di tenant Dua (tidak punya membership di sana)
with inserted as (
  insert into public.outlets (id, tenant_id, name)
  values ('55555555-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Outlet Dev')
  returning id
)
select is(
  count(*)::int, 1,
  'DEV: insert outlet ke tenant Dua (1 baris)'
) from inserted;

-- (5) dev update outlet milik tenant Dua
with updated as (
  update public.outlets set name = 'Outlet Dev (diubah)'
  where id = '55555555-2222-2222-2222-222222222222'
  returning id
)
select is(
  count(*)::int, 1,
  'DEV: update outlet di tenant Dua (1 baris)'
) from updated;

-- (6) verifikasi nama outlet berubah (sebagai postgres)
select tests_set_postgres();
select is(
  (select name from public.outlets where id = '55555555-2222-2222-2222-222222222222'),
  'Outlet Dev (diubah)',
  'DEV-VERIF: nama outlet tenant Dua berubah'
);

-- (7) dev delete outlet yang baru dibuat di tenant Dua
select tests_set_user('aaaaaaaa-1111-1111-1111-111111111111');
with deleted as (
  delete from public.outlets
  where id = '55555555-2222-2222-2222-222222222222'
  returning id
)
select is(
  count(*)::int, 1,
  'DEV: delete outlet di tenant Dua (1 baris)'
) from deleted;

-- (8) verifikasi outlet dev sudah hilang (sebagai postgres)
select tests_set_postgres();
select is(
  count(*)::int, 2,
  'DEV-VERIF: outlet kembali 2 baris (dev outlet dihapus)'
) from public.outlets
where tenant_id in ('11111111-1111-1111-1111-111111111111',
                    '22222222-2222-2222-2222-222222222222');
-- ═════════════════════════════════════════════════════════════════════════════
-- BAGIAN 3: DEV dapat menulis membership di tenant lain
-- ═════════════════════════════════════════════════════════════════════════════
-- (9) dev insert membership kasir di tenant Dua (tidak boleh self-insert)
with inserted as (
  insert into public.memberships (tenant_id, user_id, role)
  values ('22222222-2222-2222-2222-222222222222', 'cccccccc-3333-3333-3333-333333333333', 'kasir')
  returning id
)
select is(
  count(*)::int, 1,
  'DEV: insert membership ke tenant Dua (1 baris)'
) from inserted;

-- (10) verifikasi membership baru ada (sebagai postgres)
select tests_set_postgres();
select is(
  count(*)::int, 1,
  'DEV-VERIF: membership kasir di tenant Dua tersimpan'
) from public.memberships
where tenant_id = '22222222-2222-2222-2222-222222222222'
  and user_id = 'cccccccc-3333-3333-3333-333333333333';

-- (11) hapus kembali membership tes (sebagai postgres, bersihkan)
with deleted as (
  delete from public.memberships
  where tenant_id = '22222222-2222-2222-2222-222222222222'
    and user_id = 'cccccccc-3333-3333-3333-333333333333'
  returning id
)
select is(
  count(*)::int, 1,
  'DEV-VERIF: membership tes dibersihkan (1 baris)'
) from deleted;

-- ═════════════════════════════════════════════════════════════════════════════
-- BAGIAN 4: Non-dev (kasir tenant 1) tidak bisa mengakses tenant lain
-- ═════════════════════════════════════════════════════════════════════════════
select tests_set_user('cccccccc-3333-3333-3333-333333333333');

-- (12) kasir hanya melihat 1 tenant (miliknya sendiri)
select is(
  count(*)::int, 1,
  'KASIR: melihat hanya 1 tenant (milik sendiri)'
) from public.tenants;

-- (13) kasir tidak bisa membaca tenant Dua
select is(
  count(*)::int, 0,
  'KASIR: tidak bisa membaca tenant Dua (0 baris)'
) from public.tenants where id = '22222222-2222-2222-2222-222222222222';

-- (14) kasir tidak bisa membaca outlet tenant Dua
select is(
  count(*)::int, 0,
  'KASIR: tidak bisa membaca outlet tenant Dua (0 baris)'
) from public.outlets where tenant_id = '22222222-2222-2222-2222-222222222222';

-- (15) kasir tidak bisa insert outlet di tenant Dua
select throws_ok(
  $q$ insert into public.outlets (id, tenant_id, name)
       values ('66666666-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Outlet Kasir Bajakan') $q$,
  '42501',
  'new row violates row-level security policy for table "outlets"',
  'KASIR: insert outlet tenant Dua ditolak'
);

-- (16) kasir tidak bisa update outlet tenant Dua
with updated as (
  update public.outlets set name = 'disusupi kasir'
  where id = '44444444-2222-2222-2222-222222222222'
  returning id
)
select is(
  count(*)::int, 0,
  'KASIR: update outlet tenant Dua (0 baris)'
) from updated;

-- (17) verifikasi outlet tenant Dua tak berubah (sebagai postgres)
select tests_set_postgres();
select is(
  (select name from public.outlets where id = '44444444-2222-2222-2222-222222222222'),
  'Outlet Dua',
  'KASIR-VERIF: outlet tenant Dua tidak berubah'
);
-- ═════════════════════════════════════════════════════════════════════════════
-- BAGIAN 5: Dev tetap kena trigger proteksi (owner terakhir & tenant_id immutable)
-- ═════════════════════════════════════════════════════════════════════════════
-- (18) dev tidak bisa menurunkan owner terakhir di tenant 1 (A adalah owner aktif tunggal)
select tests_set_user('aaaaaaaa-1111-1111-1111-111111111111');
select throws_ok(
  $q$ update public.memberships set role = 'kasir', active = false
      where tenant_id = '11111111-1111-1111-1111-111111111111'
        and user_id = 'bbbbbbbb-2222-2222-2222-222222222222' $q$,
  'P0001',
  'Owner aktif terakhir tidak boleh dihapus, diturunkan, atau dinonaktifkan (tenant 11111111-1111-1111-1111-111111111111: hanya 0 owner aktif tersisa)',
  'DEV: menurunkan owner terakhir ditolak trigger'
);

-- (19) verifikasi owner A masih aktif (sebagai postgres)
select tests_set_postgres();
select is(
  (select active from public.memberships
   where tenant_id = '11111111-1111-1111-1111-111111111111'
     and user_id = 'bbbbbbbb-2222-2222-2222-222222222222'),
  true,
  'DEV-VERIF: owner terakhir tetap aktif'
);

-- (20) dev tidak bisa pindah tenant_id outlet (trigger immutable)
select tests_set_user('aaaaaaaa-1111-1111-1111-111111111111');
select throws_ok(
  $q$ update public.outlets set tenant_id = '22222222-2222-2222-2222-222222222222'
       where id = '33333333-1111-1111-1111-111111111111' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel outlets)',
  'DEV: pindah tenant_id outlet ditolak trigger'
);

-- (21) verifikasi outlet masih di tenant 1 (sebagai postgres)
select tests_set_postgres();
select is(
  (select tenant_id from public.outlets where id = '33333333-1111-1111-1111-111111111111'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'DEV-VERIF: outlet tetap di tenant 1'
);

select * from finish();
rollback;
