-- Tes pgTAP 0007: katalog dasar (categories & units)
-- Cakupan: RLS per perintah, isolasi tenant, parent lintas tenant ditolak,
-- tenant_id immutable, unique satuan per tenant.

begin;
select plan(32);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000001', 'authenticated', 'owner.cat@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.cat@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000003', 'authenticated', 'admin.cat@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000004', 'authenticated', 'owner2.cat@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('c2000000-0000-0000-0000-000000000001', 'Tenant Katalog A', 'bengkel'),
  ('c2000000-0000-0000-0000-000000000002', 'Tenant Katalog B', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'owner'),
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'kasir'),
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000003', 'admin'),
  ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000004', 'owner');

insert into public.categories (id, tenant_id, name) values
  ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'Oli'),
  ('c3000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001', 'Filter'),
  ('c3000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-000000000002', 'Semen');

insert into public.units (id, tenant_id, name) values
  ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'pcs'),
  ('c4000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001', 'liter'),
  ('c4000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-000000000002', 'sak');

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
-- KASIR: baca boleh, tulis ditolak
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('c1000000-0000-0000-0000-000000000002');

-- (1) kasir melihat kategori tenant-nya
select is(count(*)::int, 2, 'KASIR: melihat 2 kategori') from public.categories;

-- (2) kasir melihat satuan tenant-nya
select is(count(*)::int, 2, 'KASIR: melihat 2 satuan') from public.units;

-- (3) kasir tidak bisa insert kategori
select throws_ok(
  $q$ insert into public.categories (tenant_id, name)
      values ('c2000000-0000-0000-0000-000000000001', 'Kategori Kasir') $q$,
  '42501',
  'new row violates row-level security policy for table "categories"',
  'KASIR: insert kategori ditolak'
);

-- (4) verifikasi jumlah kategori tidak berubah
select tests_set_postgres();
select is(
  count(*)::int, 2, 'VERIF: kategori tenant A tetap 2'
) from public.categories where tenant_id = 'c2000000-0000-0000-0000-000000000001';

-- (5) kasir tidak bisa update kategori (0 baris)
select tests_set_user('c1000000-0000-0000-0000-000000000002');
with updated as (
  update public.categories set name = 'Oli Palsu'
  where id = 'c3000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: update kategori (0 baris)') from updated;

-- (6) verifikasi nama kategori tetap
select tests_set_postgres();
select is(
  (select name from public.categories where id = 'c3000000-0000-0000-0000-000000000001'),
  'Oli', 'VERIF: nama kategori tidak berubah'
);

-- (7) kasir tidak bisa delete kategori (0 baris)
select tests_set_user('c1000000-0000-0000-0000-000000000002');
with deleted as (
  delete from public.categories
  where id = 'c3000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: delete kategori (0 baris)') from deleted;

-- (8) verifikasi kategori masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: kategori Oli masih ada'
) from public.categories where id = 'c3000000-0000-0000-0000-000000000001';

-- (9) kasir tidak bisa insert satuan
select tests_set_user('c1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ insert into public.units (tenant_id, name)
      values ('c2000000-0000-0000-0000-000000000001', 'dus') $q$,
  '42501',
  'new row violates row-level security policy for table "units"',
  'KASIR: insert satuan ditolak'
);

-- (10) verifikasi jumlah satuan
select tests_set_postgres();
select is(
  count(*)::int, 2, 'VERIF: satuan tenant A tetap 2'
) from public.units where tenant_id = 'c2000000-0000-0000-0000-000000000001';

-- (11) kasir tidak bisa update satuan (0 baris)
select tests_set_user('c1000000-0000-0000-0000-000000000002');
with updated as (
  update public.units set name = 'pcs palsu'
  where id = 'c4000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: update satuan (0 baris)') from updated;

-- (12) verifikasi nama satuan
select tests_set_postgres();
select is(
  (select name from public.units where id = 'c4000000-0000-0000-0000-000000000001'),
  'pcs', 'VERIF: nama satuan tidak berubah'
);

-- (13) kasir tidak bisa delete satuan (0 baris)
select tests_set_user('c1000000-0000-0000-0000-000000000002');
with deleted as (
  delete from public.units
  where id = 'c4000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: delete satuan (0 baris)') from deleted;

-- (14) verifikasi satuan masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: satuan pcs masih ada'
) from public.units where id = 'c4000000-0000-0000-0000-000000000001';

-- ══════════════════════════════════════════════════════════════════════════
-- OWNER: CRUD
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('c1000000-0000-0000-0000-000000000001');

-- (15) owner insert kategori
with inserted as (
  insert into public.categories (id, tenant_id, name)
  values ('c3000000-0000-0000-0000-000000000004',
          'c2000000-0000-0000-0000-000000000001', 'Ban')
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert kategori (1 baris)') from inserted;

-- (16) owner update kategori
with updated as (
  update public.categories set name = 'Ban Dalam'
  where id = 'c3000000-0000-0000-0000-000000000004'
  returning id
)
select is(count(*)::int, 1, 'OWNER: update kategori (1 baris)') from updated;

-- (17) verifikasi nama kategori
select tests_set_postgres();
select is(
  (select name from public.categories where id = 'c3000000-0000-0000-0000-000000000004'),
  'Ban Dalam', 'VERIF: nama kategori berubah'
);

-- (18) owner insert satuan
select tests_set_user('c1000000-0000-0000-0000-000000000001');
with inserted as (
  insert into public.units (id, tenant_id, name)
  values ('c4000000-0000-0000-0000-000000000004',
          'c2000000-0000-0000-0000-000000000001', 'set')
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert satuan (1 baris)') from inserted;

-- (19) owner update satuan
with updated as (
  update public.units set name = 'set lengkap'
  where id = 'c4000000-0000-0000-0000-000000000004'
  returning id
)
select is(count(*)::int, 1, 'OWNER: update satuan (1 baris)') from updated;

-- (20) verifikasi nama satuan
select tests_set_postgres();
select is(
  (select name from public.units where id = 'c4000000-0000-0000-0000-000000000004'),
  'set lengkap', 'VERIF: nama satuan berubah'
);

-- (21) owner delete kategori
select tests_set_user('c1000000-0000-0000-0000-000000000001');
with deleted as (
  delete from public.categories
  where id = 'c3000000-0000-0000-0000-000000000004'
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete kategori (1 baris)') from deleted;

-- (22) verifikasi kategori hilang
select tests_set_postgres();
select is(
  count(*)::int, 0, 'VERIF: kategori Ban Dalam sudah hilang'
) from public.categories where id = 'c3000000-0000-0000-0000-000000000004';

-- (23) owner delete satuan
select tests_set_user('c1000000-0000-0000-0000-000000000001');
with deleted as (
  delete from public.units
  where id = 'c4000000-0000-0000-0000-000000000004'
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete satuan (1 baris)') from deleted;

-- (24) verifikasi satuan hilang
select tests_set_postgres();
select is(
  count(*)::int, 0, 'VERIF: satuan set lengkap sudah hilang'
) from public.units where id = 'c4000000-0000-0000-0000-000000000004';

-- ══════════════════════════════════════════════════════════════════════════
-- ISOLASI & GUARD
-- ══════════════════════════════════════════════════════════════════════════
-- (25) owner t1 tidak melihat kategori t2
select tests_set_user('c1000000-0000-0000-0000-000000000001');
select is(
  count(*)::int, 0, 'OWNER A: tidak melihat kategori tenant B'
) from public.categories where tenant_id = 'c2000000-0000-0000-0000-000000000002';

-- (26) owner t1 tidak melihat satuan t2
select is(
  count(*)::int, 0, 'OWNER A: tidak melihat satuan tenant B'
) from public.units where tenant_id = 'c2000000-0000-0000-0000-000000000002';

-- (27) owner t1 tidak bisa insert kategori ke tenant B
select throws_ok(
  $q$ insert into public.categories (tenant_id, name)
      values ('c2000000-0000-0000-0000-000000000002', 'Kategori Bajakan') $q$,
  '42501',
  'new row violates row-level security policy for table "categories"',
  'OWNER A: insert kategori tenant B ditolak'
);

-- (28) parent lintas tenant ditolak FK komposit
select throws_ok(
  $q$ update public.categories set parent_id = 'c3000000-0000-0000-0000-000000000003'
      where id = 'c3000000-0000-0000-0000-000000000001' $q$,
  '23503',
  'insert or update on table "categories" violates foreign key constraint "categories_parent_same_tenant"',
  'OWNER A: parent dari tenant B ditolak'
);

-- (29) tenant_id tidak bisa dipindah
select throws_ok(
  $q$ update public.categories set tenant_id = 'c2000000-0000-0000-0000-000000000002'
      where id = 'c3000000-0000-0000-0000-000000000001' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel categories)',
  'OWNER A: pindah tenant_id kategori ditolak trigger'
);

-- (30) nama satuan duplikat dalam tenant ditolak
select throws_ok(
  $q$ insert into public.units (tenant_id, name)
      values ('c2000000-0000-0000-0000-000000000001', 'pcs') $q$,
  '23505',
  'duplicate key value violates unique constraint "units_tenant_id_name_key"',
  'OWNER A: satuan duplikat ditolak'
);

-- (31) admin juga boleh menulis
select tests_set_user('c1000000-0000-0000-0000-000000000003');
with inserted as (
  insert into public.categories (id, tenant_id, name)
  values ('c3000000-0000-0000-0000-000000000005',
          'c2000000-0000-0000-0000-000000000001', 'Admin Cat')
  returning id
)
select is(count(*)::int, 1, 'ADMIN: insert kategori (1 baris)') from inserted;

-- (32) verifikasi kategori admin
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: kategori admin tersimpan'
) from public.categories where id = 'c3000000-0000-0000-0000-000000000005';

select * from finish();
rollback;
