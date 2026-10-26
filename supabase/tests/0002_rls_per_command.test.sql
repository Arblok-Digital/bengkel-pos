-- Tes pgTAP 0002: RLS per perintah (+ kontrol positif, verifikasi "data tak berubah")
-- Jalankan lewat: supabase test db
-- Cakupan:
--   kasir     : tidak bisa tulis tenants/outlets/memberships (verifikasi data)
--   owner     : bisa update tenant, kelola outlet, kelola membership
--   admin     : tidak bisa menyentuh baris owner / memberi role owner
--   trigger   : owner aktif terakhir tak bisa dihapus/diturunkan/dinonaktifkan
--   inactive  : membership non-aktif kehilangan semua akses
--   guard     : tenant tak bisa dibuat/hard-delete lewat API; outlet tak bisa pindah tenant
--               karena setiap tes negatif DIWUJUDKAN sebagai role tertentu via
--               SET LOCAL role + SET LOCAL request.jwt.claims (bukan postgres), kecuali di injak "verifikasi via postgres".


begin;
select plan(57);

-- ─── data uji ────────────────────────────────────────────────────────────────
create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'authenticated', 'a@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),  -- A: owner tenant 1
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'b@kasir-b.test', 'y', now(), '{"provider":"email","providers":["email"]}', now(), now()),  -- B: kasir tenant 1
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333', 'authenticated', 'b@kasir-b2.test', 'y', now(), '{"provider":"email","providers":["email"]}', now(), now()),  -- B': kasir kedua tenant 1
  ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-4444-444444444444', 'authenticated', 'b@kasir-b3.test', 'y', now(), '{"provider":"email","providers":["email"]}', now(), now()),  -- B'': kasir ketiga tenant 1
  ('00000000-0000-0000-0000-000000000000', '55555555-5555-5555-5555-555555555555', 'authenticated', 'b@kasir-b4.test', 'y', now(), '{"provider":"email","providers":["email"]}', now(), now()),  -- B''': spanduk kasir
  ('00000000-0000-0000-0000-000000000000', '66666666-6666-6666-6666-666666666666', 'authenticated', 'b@kasir-b5.test', 'y', now(), '{"provider":"email","providers":["email"]}', now(), now());   -- B'''': spanduk kasir #2

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

-- memberships (prioritas):
--   A = owner tenant 1,  B = kasir tenant 1,  C = admin tenant 1,
--   D = owner tenant 2 (satu-satunya)
insert into public.memberships (tenant_id, user_id, role)
values
  ('aaaaaaa1-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaa1-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'kasir'),
  ('aaaaaaa1-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'admin'),
  ('aaaaaaa1-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', 'owner');

-- ══════════════════════════════════════════════════════════════════════════
-- BAGIAN 1: KASIR (user B, tenant A)
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('22222222-2222-2222-2222-222222222222');

-- (1) kontrol positif: baca tenant miliknya
select is(
  count(*)::int, 1, 'KASIR-CTL: kasir membaca tenant-nya sendiri'
) from public.tenants;

-- (2) kasir tidak bisa update tenant (keluar 0 baris)
with updated as (
  update public.tenants set name = 'dirampas kasir'
  where id = 'aaaaaaa1-0000-0000-0000-000000000001'
  returning name
)
select is(
  count(*)::int, 0, 'KASIR: tidak bisa update tenants (0 baris)'
) from updated;

-- (3) verifikasi data tak berubah (sebagai postgres)
select tests_set_postgres();
select is(
  (select name from public.tenants where id = 'aaaaaaa1-0000-0000-0000-000000000001'),
  'Bengkel Maju', 'KASIR-VERIF: nama tenant unchanged'
);

-- (4) kasir tidak bisa insert outlet
select tests_set_user('22222222-2222-2222-2222-222222222222');
select throws_ok(
  $q$ insert into public.outlets (tenant_id, name)
     values ('aaaaaaa1-0000-0000-0000-000000000001', 'Outlet kasir') $q$,
  '42501',
  'new row violates row-level security policy for table "outlets"',
  'KASIR: insert outlets ditolak'
);

-- (5) kasir tidak bisa update outlet
with updated as (
  update public.outlets set name = 'Outlet Maling'
  where id = 'bbbbbbb1-0000-0000-0000-000000000001'
  returning name
)
select is(
  count(*)::int, 0, 'KASIR: tidak bisa update outlets (0 baris)'
) from updated;

-- (6) verifikasi nama outlet unchanged
select tests_set_postgres();
select is(
  (select name from public.outlets where id = 'bbbbbbb1-0000-0000-0000-000000000001'),
  'Outlet A', 'KASIR-VERIF: nama outlet unchanged'
);

-- (7) kasir tidak bisa delete outlet
select tests_set_user('22222222-2222-2222-2222-222222222222');
with deleted as (
  delete from public.outlets where id = 'bbbbbbb1-0000-0000-0000-000000000001' returning id
)
select is(
  count(*)::int, 0, 'KASIR: tidak bisa delete outlets (0 baris)'
) from deleted;

-- (8) verifikasi total outlets masih 2 (sebagai postgres)
select tests_set_postgres();
select is(
  count(*)::int, 2, 'KASIR-VERIF: total outlets tetap 2'
) from public.outlets;

-- (9) kasir tidak bisa delete membership milik owner
select tests_set_user('22222222-2222-2222-2222-222222222222');
with deleted as (
  delete from public.memberships
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
    and user_id = '11111111-1111-1111-1111-111111111111'
  returning id
)
select is(
  count(*)::int, 0, 'KASIR: tidak bisa delete memberships milik owner (0 baris)'
) from deleted;

-- (10) verifikasi membership owner masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'KASIR-VERIF: membership owner masih ada'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
  and user_id = '11111111-1111-1111-1111-111111111111';

-- (11) kasir tidak bisa mengubah membership dirinya (0 baris)
select tests_set_user('22222222-2222-2222-2222-222222222222');
with updated as (
  update public.memberships set role = 'owner'
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
    and user_id = '22222222-2222-2222-2222-222222222222'
  returning id
)
select is(
  count(*)::int, 0, 'KASIR: tidak bisa mengubah membership dirinya (0 baris)'
) from updated;

-- (12) verifikasi role kasir untuk B
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
      and user_id = '22222222-2222-2222-2222-222222222222'),
  'kasir', 'KASIR-VERIF: role B tetap kasir'
);

-- (13) kontrol positif: kasir MELIHAT memberships tenant-nya (owner + kasir)
select tests_set_user('22222222-2222-2222-2222-222222222222');
select is(
  count(*)::int, 3, 'KASIR-CTL: kasir membaca memberships tenant-nya (owner+kasir+admin = 3)'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001';

-- (14) kasir tidak bisa membaca memberships tenant lain
select is(
  count(*)::int, 0, 'KASIR: tidak bisa baca memberships tenant B (0 baris)'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002';

-- (15) kasir tidak bisa insert memberships
select throws_ok(
  $q$ insert into public.memberships (tenant_id, user_id, role)
     values ('aaaaaaa1-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555', 'kasir') $q$,
  '42501',
  'new row violates row-level security policy for table "memberships"',
  'KASIR: insert memberships ditolak'
);

-- ══════════════════════════════════════════════════════════════════════════
-- BAGIAN 2: OWNER (user A, tenant A)
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('11111111-1111-1111-1111-111111111111');

-- (16) kontrol positif: owner mengubah nama tenant
with updated as (
  update public.tenants set name = 'Bengkel Maju Jaya'
  where id = 'aaaaaaa1-0000-0000-0000-000000000001'
  returning id
)
select is(
  count(*)::int, 1, 'OWNER-CTL: owner mengubah tenants (1 baris)'
) from updated;

-- (17) verifikasi nama tenant bertahap
select tests_set_postgres();
select is(
  (select name from public.tenants where id = 'aaaaaaa1-0000-0000-0000-000000000001'),
  'Bengkel Maju Jaya', 'OWNER-VERIF: nama tenant berubah'
);

-- (18) owner menambahkan outlet baru
select tests_set_user('11111111-1111-1111-1111-111111111111');
with inserted as (
  insert into public.outlets (id, tenant_id, name)
  values ('bbbbbbb1-0000-0000-0000-000000000003', 'aaaaaaa1-0000-0000-0000-000000000001', 'Outlet A2')
  returning id
)
select is(
  count(*)::int, 1, 'OWNER-CTL: owner insert outlets (1 baris)'
) from inserted;

-- (19) verifikasi outlet baru
select tests_set_postgres();
select is(
  count(*)::int, 2, 'OWNER-VERIF: 2 outlets di tenant A'
) from public.outlets
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001';

-- (20) owner menghapus kembali outlet baru
select tests_set_user('11111111-1111-1111-1111-111111111111');
with deleted as (
  delete from public.outlets where id = 'bbbbbbb1-0000-0000-0000-000000000003' returning id
)
select is(
  count(*)::int, 1, 'OWNER-CTL: owner delete outlets (1 baris)'
) from deleted;

-- (21) verifikasi outlet new帮你 dihapus
select tests_set_postgres();
select is(
  count(*)::int, 1, 'OWNER-VERIF: outlet baru hilang (1 outlet di tenant A)'
) from public.outlets
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001';

-- owner menambahkan membership kasir baru (user 6666…)
select tests_set_user('11111111-1111-1111-1111-111111111111');
with inserted as (
  insert into public.memberships (tenant_id, user_id, role)
  values ('aaaaaaa1-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555', 'kasir')
  returning id
)
select is(
  count(*)::int, 1, 'OWNER-CTL: owner insert memberships kasir (1 baris)'
) from inserted;

-- verifikasi membership E
select tests_set_postgres();
select is(
  count(*)::int, 1, 'OWNER-VERIF: membership B4 kasir ada'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
  and user_id = '55555555-5555-5555-5555-555555555555';

-- owner menghapus membership kasir tsb
select tests_set_user('11111111-1111-1111-1111-111111111111');
with deleted as (
  delete from public.memberships
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
    and user_id = '55555555-5555-5555-5555-555555555555'
  returning id
)
select is(
  count(*)::int, 1, 'OWNER-CTL: owner delete memberships kasir (1 baris)'
) from deleted;

-- verifikasi membership E hilang
select tests_set_postgres();
select is(
  count(*)::int, 0, 'OWNER-VERIF: membership B4 hilang'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
  and user_id = '55555555-5555-5555-5555-555555555555';

-- owner TIDAK bisa menambah membership untuk dirinya sendiri
select tests_set_user('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $q$ insert into public.memberships (tenant_id, user_id, role)
     values ('aaaaaaa1-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner') $q$,
  '42501',
  'new row violates row-level security policy for table "memberships"',
  'OWNER: insert membership dirinya sendiri ditolak (with check) '
);

-- verifikasi memberships tenant A member user A masih 1
select tests_set_postgres();
select is(
  count(*)::int, 1, 'OWNER-VERIF: tetap 1 membership untuk owner A'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
  and user_id = '11111111-1111-1111-1111-111111111111';

-- ══════════════════════════════════════════════════════════════════════════
-- BAGIAN 3: ADMIN (user C, tenant A)
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('33333333-3333-3333-3333-333333333333');

-- (28) kontrol positif: admin juga boleh update tenant
with updated as (
  update public.tenants set name = 'Bengkel Maju Jaya'
  where id = 'aaaaaaa1-0000-0000-0000-000000000001'
  returning id
)
select is(
  count(*)::int, 1, 'ADMIN-CTL: admin mengubah tenants (1 baris)'
) from updated;

-- (29) verifikasi
select tests_set_postgres();
select is(
  (select name from public.tenants where id = 'aaaaaaa1-0000-0000-0000-000000000001'),
  'Bengkel Maju Jaya', 'ADMIN-VERIF: nama tenant tetap'
);

-- (30) admin TIDAK bisa menurunkan owner (baris owner: 0 baris keluar)
select tests_set_user('33333333-3333-3333-3333-333333333333');
with updated as (
  update public.memberships set role = 'kasir'
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
    and user_id = '11111111-1111-1111-1111-111111111111'
  returning id
)
select is(
  count(*)::int, 0, 'ADMIN: tidak bisa menurunkan owner (0 baris)'
) from updated;

-- (31) verifikasi owner tetap owner
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
      and user_id = '11111111-1111-1111-1111-111111111111'),
  'owner', 'ADMIN-VERIF: owner tetap owner'
);

-- (32) admin TIDAK bisa menghapus owner
select tests_set_user('33333333-3333-3333-3333-333333333333');
with deleted as (
  delete from public.memberships
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
    and user_id = '11111111-1111-1111-1111-111111111111'
  returning id
)
select is(
  count(*)::int, 0, 'ADMIN: tidak bisa delete memberships milik owner (0 baris)'
) from deleted;

-- (33) verifikasi membership owner masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'ADMIN-VERIF: membership owner masih ada (cukup 1)'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
  and user_id = '11111111-1111-1111-1111-111111111111';

-- (34) admin TIDAK bisa memberi role owner ke kasir
select tests_set_user('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $q$ update public.memberships set role = 'owner'
     where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
       and user_id = '22222222-2222-2222-2222-222222222222' $q$,
  '42501',
  'new row violates row-level security policy for table "memberships"',
  'ADMIN: memberi role owner ditolak (with check)'
);

-- (35) verifikasi kasir B masih kasir
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
      and user_id = '22222222-2222-2222-2222-222222222222'),
  'kasir', 'ADMIN-VERIF: kasir B tetap kasir'
);

-- (36) kontrol positif: admin bisa mem-promote kasir ke admin
select tests_set_user('33333333-3333-3333-3333-333333333333');
with updated as (
  update public.memberships set role = 'admin'
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
    and user_id = '22222222-2222-2222-2222-222222222222'
  returning id
)
select is(
  count(*)::int, 1, 'ADMIN-CTL: admin mem-promote kasir ke admin (1 baris)'
) from updated;

-- (37) verifikasi kasir B jadi admin
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
      and user_id = '22222222-2222-2222-2222-222222222222'),
  'admin', 'ADMIN-VERIF: kasir B naik ke admin'
);

-- (38) admin mengembalikan kasir sebagaimana awal
select tests_set_user('33333333-3333-3333-3333-333333333333');
with updated as (
  update public.memberships set role = 'kasir'
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
    and user_id = '22222222-2222-2222-2222-222222222222'
  returning id
)
select is(
  count(*)::int, 1, 'ADMIN-CTL: admin menurunkan kembali ke kasir (1 baris)'
) from updated;

-- (39) verifikasi
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
      and user_id = '22222222-2222-2222-2222-222222222222'),
  'kasir', 'ADMIN-VERIF: kasir B kembali kasir'
);

-- (40) admin tidak bisa mengubah membership dirinya sendiri (0 baris)
select tests_set_user('33333333-3333-3333-3333-333333333333');
with updated as (
  update public.memberships set role = 'owner'
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
    and user_id = '33333333-3333-3333-3333-333333333333'
  returning id
)
select is(
  count(*)::int, 0, 'ADMIN: tidak bisa mengubah membership dirinya (0 baris)'
) from updated;

-- (41) verifikasi role admin C
select tests_set_postgres();
select is(
  (select role from public.memberships
    where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
      and user_id = '33333333-3333-3333-3333-333333333333'),
  'admin', 'ADMIN-VERIF: role C tetap admin'
);

-- ══════════════════════════════════════════════════════════════════════════
-- BAGIAN 4: OWNER TERAKHIR (tenant B punya 1 owner: user D) —
-- trigger melarang penurunan/nonaktif/hapus oleh SIAPA PUN (termasuk postgres)
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_postgres();

-- (42) turunkan owner D → trigger lempar error
select throws_ok(
  $q$ update public.memberships set role = 'kasir'
     where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002'
       and user_id = '44444444-4444-4444-4444-444444444444' $q$,
  'P0001',
  'Owner aktif terakhir tidak boleh dihapus, diturunkan, atau dinonaktifkan (tenant aaaaaaa1-0000-0000-0000-000000000002: hanya 0 owner aktif tersisa)',
  'TRIGGER: penurunan owner terakhir ditolak'
);

-- (43) verifikasi owner tetap owner + active
select is(
  count(*)::int, 1, 'TRIGGER-VERIF: owner D tetap owner active'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002'
  and user_id = '44444444-4444-4444-4444-444444444444'
  and role = 'owner'
  and active;

-- (44) nonaktifkan owner D → trigger lempar error
select throws_ok(
  $q$ update public.memberships set active = false
     where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002'
       and user_id = '44444444-4444-4444-4444-444444444444' $q$,
  'P0001',
  'Owner aktif terakhir tidak boleh dihapus, diturunkan, atau dinonaktifkan (tenant aaaaaaa1-0000-0000-0000-000000000002: hanya 0 owner aktif tersisa)',
  'TRIGGER: nonaktifkan owner terakhir ditolak'
);

-- (45) verifikasi
select is(
  count(*)::int, 1, 'TRIGGER-VERIF: owner D tetap active (setelah mencoba nonaktif)'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002'
  and user_id = '44444444-4444-4444-4444-444444444444'
  and active;

-- (46) hapus owner D → trigger lempar error
select throws_ok(
  $q$ delete from public.memberships
     where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002'
       and user_id = '44444444-4444-4444-4444-444444444444' $q$,
  'P0001',
  'Owner aktif terakhir tidak boleh dihapus, diturunkan, atau dinonaktifkan (tenant aaaaaaa1-0000-0000-0000-000000000002: hanya 0 owner aktif tersisa)',
  'TRIGGER: hapus owner terakhir ditolak'
);

-- (47) verifikasi
select is(
  count(*)::int, 1, 'TRIGGER-VERIF: owner D tetap ada (setelah mencoba delete)'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002'
  and user_id = '44444444-4444-4444-4444-444444444444';

-- ══════════════════════════════════════════════════════════════════════════
-- BAGIAN 5: MEMBERSHIP NONAKTIF = tanpa akses semua
-- ══════════════════════════════════════════════════════════════════════════
-- matikan Bd: kasir B nonaktif (sebagai postgres)
update public.memberships set active = false
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
  and user_id = '22222222-2222-2222-2222-222222222222';

select tests_set_user('22222222-2222-2222-2222-222222222222');

-- (49) B tidak lagi melihat tenant
select is(
  count(*)::int, 0, 'INACTIVE: B nonaktif tidak melihat tenants (0 baris)'
) from public.tenants;

select is(
  count(*)::int, 0, 'INACTIVE: B nonaktif tidak melihat memberships (0 baris)'
) from public.memberships
where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001';

select throws_ok(
  $q$ insert into public.outlets (tenant_id, name)
     values ('aaaaaaa1-0000-0000-0000-000000000001', 'Outlet nonaktif') $q$,
  '42501',
  'new row violates row-level security policy for table "outlets"',
  'INACTIVE: insert outlets ditolak'
);

-- (52) aktifkan kembali B sebagai postgres
select tests_set_postgres();
with updated as (
  update public.memberships set active = true
  where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
    and user_id = '22222222-2222-2222-2222-222222222222'
  returning id
)
select is(
  count(*)::int, 1, 'INACTIVE-CTL: re-aktifkan B (1 baris)'
) from updated;

select is(
  (select active from public.memberships
    where tenant_id = 'aaaaaaa1-0000-0000-0000-000000000001'
      and user_id = '22222222-2222-2222-2222-222222222222'),
  true, 'INACTIVE-VERIF: B kembali aktif'
);

-- ══════════════════════════════════════════════════════════════════════════
-- BAGIAN 6: TENANT tak bisa dibuat/hard-delete lewat API; outlet tak bisa pindah tenant
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('11111111-1111-1111-1111-111111111111');

-- (54) owner tidak bisa delete tenant (tanpa policy DELETE)
with deleted as (
  delete from public.tenants where id = 'aaaaaaa1-0000-0000-0000-000000000001' returning id
)
select is(
  count(*)::int, 0, 'TENANT: delete tenant lewat API (0 baris)'
) from deleted;

-- (55) verifikasi tenant tetap ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'TENANT-VERIF: tenant A tetap ada'
) from public.tenants
where id = 'aaaaaaa1-0000-0000-0000-000000000001';

-- (56) owner tidak bisa insert tenant baru (tanpa policy INSERT)
select tests_set_user('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $q$ insert into public.tenants (id, name, business_type)
     values ('aaaaaaa1-0000-0000-0000-000000000009', 'Tenant bajakan', 'bengkel') $q$,
  '42501',
  'new row violates row-level security policy for table "tenants"',
  'TENANT: insert tenant lewat API ditolak'
);

-- (57) outlet tidak bisa pindah tenant
select throws_ok(
  $q$ update public.outlets set tenant_id = 'aaaaaaa1-0000-0000-0000-000000000002'
     where id = 'bbbbbbb1-0000-0000-0000-000000000001' $q$,
  '42501',
  'new row violates row-level security policy for table "outlets"',
  'OUTLET: pindah outlet ke tenant lain ditolak (with check)'
);

-- (58) verifikasi outlet A tetap di tenant A
select tests_set_postgres();
select is(
  (select tenant_id from public.outlets where id = 'bbbbbbb1-0000-0000-0000-000000000001'),
  'aaaaaaa1-0000-0000-0000-000000000001'::uuid,
  'OUTLET-VERIF: outlet A tetap memuat tenant A'
);

select * from finish();
rollback;
