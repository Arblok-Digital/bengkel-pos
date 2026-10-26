-- Tes pgTAP 0003: tenant_id immutable + set_created_by + inactive tanpa akses
-- Jalankan lewat: supabase test db
-- Fokus audit:
--   A. tenant_id tidak bisa dipindah lewat UPDATE, termasuk oleh user yang
--      owner di KEDUA tenant (celah yang tidak tertangkap tes 0002 #57).
--   B. created_by dipaksa auth.uid() saat ada sesi; nilai server (tanpa sesi)
--      tetap dihormati.
--   C. membership active=false kehilangan SELECT/UPDATE/DELETE, bukan hanya SELECT.
--   D. kasir tidak bisa hard-delete tenant.

begin;
select plan(30);

create extension if not exists pgtap with schema extensions;

-- ─── data uji ────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '99999999-9999-9999-9999-999999999901', 'authenticated', 'h@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),  -- H: owner tenant 1 + 2
  ('00000000-0000-0000-0000-000000000000', '99999999-9999-9999-9999-999999999902', 'authenticated', 'p@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),  -- P: owner tenant 1
  ('00000000-0000-0000-0000-000000000000', '99999999-9999-9999-9999-999999999903', 'authenticated', 'k@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());  -- K: kasir tenant 1

insert into public.tenants (id, name, business_type) values
  ('ddddddd1-0000-0000-0000-000000000001', 'Tenant Satu', 'bengkel'),
  ('ddddddd1-0000-0000-0000-000000000002', 'Tenant Dua', 'toko_bangunan');

insert into public.outlets (id, tenant_id, name) values
  ('eeeeeee1-0000-0000-0000-000000000001', 'ddddddd1-0000-0000-0000-000000000001', 'Outlet Satu'),
  ('eeeeeee1-0000-0000-0000-000000000002', 'ddddddd1-0000-0000-0000-000000000002', 'Outlet Dua');

insert into public.memberships (tenant_id, user_id, role) values
  ('ddddddd1-0000-0000-0000-000000000001', '99999999-9999-9999-9999-999999999901', 'owner'),
  ('ddddddd1-0000-0000-0000-000000000002', '99999999-9999-9999-9999-999999999901', 'owner'),
  ('ddddddd1-0000-0000-0000-000000000001', '99999999-9999-9999-9999-999999999902', 'owner'),
  ('ddddddd1-0000-0000-0000-000000000001', '99999999-9999-9999-9999-999999999903', 'kasir');

-- ─── helper sesi (sama dengan 0001/0002) ─────────────────────────────────────
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
-- A. tenant_id immutable
-- ══════════════════════════════════════════════════════════════════════════

-- (1) kontrol positif: owner boleh mengubah nama outlet di tenant-nya
select tests_set_user('99999999-9999-9999-9999-999999999902');
with updated as (
  update public.outlets set name = 'Outlet Satu (ubah)'
  where id = 'eeeeeee1-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 1, 'CTL: owner boleh ubah nama outlet (1 baris)') from updated;

-- (2) verifikasi nama berubah
select tests_set_postgres();
select is(
  (select name from public.outlets where id = 'eeeeeee1-0000-0000-0000-000000000001'),
  'Outlet Satu (ubah)', 'VERIF: nama outlet berubah'
);

-- (3) owner satu tenant: pindah outlet ditolak trigger (bukan 42501)
select tests_set_user('99999999-9999-9999-9999-999999999902');
select throws_ok(
  $q$ update public.outlets set tenant_id = 'ddddddd1-0000-0000-0000-000000000002'
      where id = 'eeeeeee1-0000-0000-0000-000000000001' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel outlets)',
  'OUTLET: pindah tenant ditolak trigger (aktor single-tenant)'
);

-- (4) verifikasi outlet tetap di tenant 1
select tests_set_postgres();
select is(
  (select tenant_id from public.outlets where id = 'eeeeeee1-0000-0000-0000-000000000001'),
  'ddddddd1-0000-0000-0000-000000000001'::uuid,
  'VERIF: outlet tetap di tenant 1'
);

-- (5) H owner di KEDUA tenant: pindah outlet tetap ditolak
select tests_set_user('99999999-9999-9999-9999-999999999901');
select throws_ok(
  $q$ update public.outlets set tenant_id = 'ddddddd1-0000-0000-0000-000000000002'
      where id = 'eeeeeee1-0000-0000-0000-000000000001' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel outlets)',
  'OUTLET: pindah tenant ditolak walau aktor owner dua tenant'
);

-- (6) verifikasi
select tests_set_postgres();
select is(
  (select tenant_id from public.outlets where id = 'eeeeeee1-0000-0000-0000-000000000001'),
  'ddddddd1-0000-0000-0000-000000000001'::uuid,
  'VERIF: outlet tetap di tenant 1 setelah percobaan multi-tenant'
);

-- (7) H memindahkan baris membership kasir K antar tenant
select tests_set_user('99999999-9999-9999-9999-999999999901');
select throws_ok(
  $q$ update public.memberships set tenant_id = 'ddddddd1-0000-0000-0000-000000000002'
      where tenant_id = 'ddddddd1-0000-0000-0000-000000000001'
        and user_id = '99999999-9999-9999-9999-999999999903' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel memberships)',
  'MEMBERSHIP: pindah baris antar tenant ditolak trigger'
);

-- (8) verifikasi membership K tetap di tenant 1
select tests_set_postgres();
select is(
  (select tenant_id from public.memberships
    where user_id = '99999999-9999-9999-9999-999999999903'),
  'ddddddd1-0000-0000-0000-000000000001'::uuid,
  'VERIF: membership K tetap di tenant 1'
);

-- (9) kontrol positif: trigger tidak menghalangi update kolom lain
select tests_set_user('99999999-9999-9999-9999-999999999901');
with updated as (
  update public.memberships set role = 'gudang'
  where tenant_id = 'ddddddd1-0000-0000-0000-000000000001'
    and user_id = '99999999-9999-9999-9999-999999999903'
  returning id
)
select is(count(*)::int, 1, 'CTL: owner tetap bisa ubah role kasir (1 baris)') from updated;

-- (10) verifikasi role berubah
select tests_set_postgres();
select is(
  (select role from public.memberships
    where user_id = '99999999-9999-9999-9999-999999999903'),
  'gudang', 'VERIF: role K berubah menjadi gudang'
);

-- (11) kontrol positif: update outlet tanpa menyentuh tenant_id
select tests_set_user('99999999-9999-9999-9999-999999999901');
with updated as (
  update public.outlets set name = 'Outlet Satu (lagi)'
  where id = 'eeeeeee1-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 1, 'CTL: update outlet biasa tetap jalan (1 baris)') from updated;

-- (12) verifikasi
select tests_set_postgres();
select is(
  (select name from public.outlets where id = 'eeeeeee1-0000-0000-0000-000000000001'),
  'Outlet Satu (lagi)', 'VERIF: nama outlet terbaru tersimpan'
);

-- ══════════════════════════════════════════════════════════════════════════
-- B. set_created_by
-- ══════════════════════════════════════════════════════════════════════════

-- (13) klien mengirim created_by palsu → dipaksa ke sesi (owner P)
select tests_set_user('99999999-9999-9999-9999-999999999902');
with inserted as (
  insert into public.outlets (id, tenant_id, name, created_by)
  values ('eeeeeee1-0000-0000-0000-000000000003',
          'ddddddd1-0000-0000-0000-000000000001',
          'Outlet Tiga',
          '99999999-9999-9999-9999-999999999903')
  returning created_by
)
select is(
  created_by,
  '99999999-9999-9999-9999-999999999902'::uuid,
  'CREATED_BY: nilai kiriman klien diabaikan, dipaksa auth.uid()'
) from inserted;

-- (14) verifikasi dari postgres
select tests_set_postgres();
select is(
  (select created_by from public.outlets where id = 'eeeeeee1-0000-0000-0000-000000000003'),
  '99999999-9999-9999-9999-999999999902'::uuid,
  'VERIF: created_by tersimpan = user sesi'
);

-- (15) tanpa sesi (server/service): created_by eksplisit tetap dihormati
with inserted as (
  insert into public.outlets (id, tenant_id, name, created_by)
  values ('eeeeeee1-0000-0000-0000-000000000004',
          'ddddddd1-0000-0000-0000-000000000001',
          'Outlet Empat',
          '99999999-9999-9999-9999-999999999903')
  returning created_by
)
select is(
  created_by,
  '99999999-9999-9999-9999-999999999903'::uuid,
  'CREATED_BY: tanpa sesi, created_by eksplisit tidak ditimpa'
) from inserted;

-- (16) verifikasi
select is(
  (select created_by from public.outlets where id = 'eeeeeee1-0000-0000-0000-000000000004'),
  '99999999-9999-9999-9999-999999999903'::uuid,
  'VERIF: created_by server tersimpan apa adanya'
);

-- ══════════════════════════════════════════════════════════════════════════
-- C. membership inactive = tanpa akses (SELECT/UPDATE/DELETE)
-- ══════════════════════════════════════════════════════════════════════════

-- (17) kontrol: nonaktifkan K (kasir)
with updated as (
  update public.memberships set active = false
  where tenant_id = 'ddddddd1-0000-0000-0000-000000000001'
    and user_id = '99999999-9999-9999-9999-999999999903'
  returning id
)
select is(count(*)::int, 1, 'CTL: postgres menonaktifkan K (1 baris)') from updated;

-- (18) K tidak melihat tenant
select tests_set_user('99999999-9999-9999-9999-999999999903');
select is(
  count(*)::int, 0, 'INACTIVE: K tidak melihat tenants (0 baris)'
) from public.tenants;

-- (19) K tidak bisa update tenant
with updated as (
  update public.tenants set name = 'dirampas nonaktif'
  where id = 'ddddddd1-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'INACTIVE: K tidak bisa update tenants (0 baris)') from updated;

-- (20) verifikasi nama tenant
select tests_set_postgres();
select is(
  (select name from public.tenants where id = 'ddddddd1-0000-0000-0000-000000000001'),
  'Tenant Satu', 'VERIF: nama tenant tidak berubah'
);

-- (21) K tidak bisa delete outlet
select tests_set_user('99999999-9999-9999-9999-999999999903');
with deleted as (
  delete from public.outlets
  where id = 'eeeeeee1-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'INACTIVE: K tidak bisa delete outlets (0 baris)') from deleted;

-- (22) verifikasi outlet masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: outlet tenant 1 masih ada'
) from public.outlets where id = 'eeeeeee1-0000-0000-0000-000000000001';

-- (23) K tidak bisa mengaktifkan dirinya sendiri
select tests_set_user('99999999-9999-9999-9999-999999999903');
with updated as (
  update public.memberships set active = true
  where tenant_id = 'ddddddd1-0000-0000-0000-000000000001'
    and user_id = '99999999-9999-9999-9999-999999999903'
  returning id
)
select is(count(*)::int, 0, 'INACTIVE: K tidak bisa mengaktifkan dirinya (0 baris)') from updated;

-- (24) verifikasi K tetap nonaktif
select tests_set_postgres();
select is(
  (select active from public.memberships
    where user_id = '99999999-9999-9999-9999-999999999903'),
  false, 'VERIF: K tetap nonaktif'
);

-- (25) K tidak bisa delete membership owner
select tests_set_user('99999999-9999-9999-9999-999999999903');
with deleted as (
  delete from public.memberships
  where tenant_id = 'ddddddd1-0000-0000-0000-000000000001'
    and user_id = '99999999-9999-9999-9999-999999999902'
  returning id
)
select is(count(*)::int, 0, 'INACTIVE: K tidak bisa delete membership owner (0 baris)') from deleted;

-- (26) verifikasi membership owner masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: membership owner P masih ada'
) from public.memberships
where tenant_id = 'ddddddd1-0000-0000-0000-000000000001'
  and user_id = '99999999-9999-9999-9999-999999999902';

-- (27) kontrol: aktifkan kembali K
with updated as (
  update public.memberships set active = true
  where tenant_id = 'ddddddd1-0000-0000-0000-000000000001'
    and user_id = '99999999-9999-9999-9999-999999999903'
  returning id
)
select is(count(*)::int, 1, 'CTL: postgres mengaktifkan kembali K (1 baris)') from updated;

-- (28) K kembali melihat tenant
select tests_set_user('99999999-9999-9999-9999-999999999903');
select is(
  count(*)::int, 1, 'INACTIVE-CTL: K kembali melihat tenant (1 baris)'
) from public.tenants;

-- (29) kasir tidak bisa hard-delete tenant
with deleted as (
  delete from public.tenants
  where id = 'ddddddd1-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: delete tenant (0 baris)') from deleted;

-- (30) verifikasi tenant masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: tenant 1 tetap ada'
) from public.tenants where id = 'ddddddd1-0000-0000-0000-000000000001';

select * from finish();
rollback;
