-- Tes pgTAP 0010: pelanggan + pemasok (T2.4)
begin;
select plan(30);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000001', 'authenticated', 'owner.contact@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.contact@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000003', 'authenticated', 'admin.contact@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000004', 'authenticated', 'owner2.contact@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('f2000000-0000-0000-0000-000000000001', 'Tenant Kontak A', 'bengkel'),
  ('f2000000-0000-0000-0000-000000000002', 'Tenant Kontak B', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'owner'),
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000002', 'kasir'),
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000003', 'admin'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000004', 'owner');

insert into public.customers (id, tenant_id, name, phone, tier_id, credit_limit) values
  ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
   'Budi', '0811', (select id from public.price_tiers
                    where tenant_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Umum'), 500000),
  ('f3000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001',
   'Siti', '0812', null, 0),
  ('f3000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000002',
   'Andi', '0813', null, 0);

insert into public.suppliers (id, tenant_id, name, phone, payment_terms_days) values
  ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
   'Toko Oli', '0821', 0),
  ('f4000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000002',
   'Supplier B', '0822', 0);

-- tier tetap milik tenant B (untuk uji FK lintas tenant)
insert into public.price_tiers (id, tenant_id, name)
values ('f5000000-0000-0000-0000-000000000002',
        'f2000000-0000-0000-0000-000000000002', 'Tier B');

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
select tests_set_user('f1000000-0000-0000-0000-000000000002');

-- (1) kasir melihat pelanggan
select is(count(*)::int, 2, 'KASIR: melihat 2 pelanggan') from public.customers;

-- (2) kasir melihat pemasok
select is(count(*)::int, 1, 'KASIR: melihat 1 pemasok') from public.suppliers;

-- (3) kasir tidak bisa insert pelanggan
select throws_ok(
  $q$ insert into public.customers (tenant_id, name)
      values ('f2000000-0000-0000-0000-000000000001', 'Pelanggan Kasir') $q$,
  '42501',
  'new row violates row-level security policy for table "customers"',
  'KASIR: insert pelanggan ditolak'
);

-- (4) verifikasi jumlah pelanggan
select tests_set_postgres();
select is(
  count(*)::int, 2, 'VERIF: pelanggan tenant A tetap 2'
) from public.customers where tenant_id = 'f2000000-0000-0000-0000-000000000001';

-- (5) kasir tidak bisa update pelanggan
select tests_set_user('f1000000-0000-0000-0000-000000000002');
with updated as (
  update public.customers set name = 'Diubah Kasir'
  where id = 'f3000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: update pelanggan (0 baris)') from updated;

-- (6) verifikasi nama pelanggan
select tests_set_postgres();
select is(
  (select name from public.customers where id = 'f3000000-0000-0000-0000-000000000001'),
  'Budi', 'VERIF: nama pelanggan tidak berubah'
);

-- (7) kasir tidak bisa delete pelanggan
select tests_set_user('f1000000-0000-0000-0000-000000000002');
with deleted as (
  delete from public.customers
  where id = 'f3000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: delete pelanggan (0 baris)') from deleted;

-- (8) verifikasi pelanggan masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: pelanggan Budi masih ada'
) from public.customers where id = 'f3000000-0000-0000-0000-000000000001';

-- (9) kasir tidak bisa insert pemasok
select tests_set_user('f1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ insert into public.suppliers (tenant_id, name)
      values ('f2000000-0000-0000-0000-000000000001', 'Pemasok Kasir') $q$,
  '42501',
  'new row violates row-level security policy for table "suppliers"',
  'KASIR: insert pemasok ditolak'
);

-- (10) verifikasi jumlah pemasok
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: pemasok tenant A tetap 1'
) from public.suppliers where tenant_id = 'f2000000-0000-0000-0000-000000000001';

-- (11) kasir tidak bisa update pemasok
select tests_set_user('f1000000-0000-0000-0000-000000000002');
with updated as (
  update public.suppliers set name = 'Diubah Kasir'
  where id = 'f4000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: update pemasok (0 baris)') from updated;

-- (12) verifikasi nama pemasok
select tests_set_postgres();
select is(
  (select name from public.suppliers where id = 'f4000000-0000-0000-0000-000000000001'),
  'Toko Oli', 'VERIF: nama pemasok tidak berubah'
);

-- (13) kasir tidak bisa delete pemasok
select tests_set_user('f1000000-0000-0000-0000-000000000002');
with deleted as (
  delete from public.suppliers
  where id = 'f4000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: delete pemasok (0 baris)') from deleted;

-- (14) verifikasi pemasok masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: pemasok Toko Oli masih ada'
) from public.suppliers where id = 'f4000000-0000-0000-0000-000000000001';

-- ══════════════════════════════════════════════════════════════════════════
-- OWNER: CRUD
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000001');

-- (15) owner insert pelanggan
with inserted as (
  insert into public.customers (id, tenant_id, name, phone, tier_id, credit_limit)
  values ('f3000000-0000-0000-0000-000000000004',
          'f2000000-0000-0000-0000-000000000001', 'Joko', '0814',
          (select id from public.price_tiers
            where tenant_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Langganan'),
          1000000)
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert pelanggan (1 baris)') from inserted;

-- (16) verifikasi pelanggan baru
select tests_set_postgres();
select is(
  (select credit_limit from public.customers where id = 'f3000000-0000-0000-0000-000000000004'),
  1000000::bigint, 'VERIF: limit kredit tersimpan'
);

-- (17) owner update pelanggan
select tests_set_user('f1000000-0000-0000-0000-000000000001');
with updated as (
  update public.customers set name = 'Joko Baru', credit_limit = 2000000
  where id = 'f3000000-0000-0000-0000-000000000004'
  returning id
)
select is(count(*)::int, 1, 'OWNER: update pelanggan (1 baris)') from updated;

-- (18) verifikasi update pelanggan
select tests_set_postgres();
select is(
  (select credit_limit from public.customers where id = 'f3000000-0000-0000-0000-000000000004'),
  2000000::bigint, 'VERIF: limit kredit berubah'
);

-- (19) owner delete pelanggan
select tests_set_user('f1000000-0000-0000-0000-000000000001');
with deleted as (
  delete from public.customers
  where id = 'f3000000-0000-0000-0000-000000000004'
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete pelanggan (1 baris)') from deleted;

-- (20) verify pelanggan hilang
select tests_set_postgres();
select is(
  count(*)::int, 0, 'VERIF: pelanggan Joko Baru hilang'
) from public.customers where id = 'f3000000-0000-0000-0000-000000000004';

-- (21) owner insert pemasok
select tests_set_user('f1000000-0000-0000-0000-000000000001');
with inserted as (
  insert into public.suppliers (id, tenant_id, name, phone, payment_terms_days)
  values ('f4000000-0000-0000-0000-000000000003',
          'f2000000-0000-0000-0000-000000000001', 'Supplier Baru', '0823', 30)
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert pemasok (1 baris)') from inserted;

-- (22) verifikasi termin
select tests_set_postgres();
select is(
  (select payment_terms_days from public.suppliers where id = 'f4000000-0000-0000-0000-000000000003'),
  30, 'VERIF: termin pembayaran tersimpan'
);

-- (23) owner update pemasok
select tests_set_user('f1000000-0000-0000-0000-000000000001');
with updated as (
  update public.suppliers set payment_terms_days = 14
  where id = 'f4000000-0000-0000-0000-000000000003'
  returning id
)
select is(count(*)::int, 1, 'OWNER: update pemasok (1 baris)') from updated;

-- (24) owner delete pemasok
with deleted as (
  delete from public.suppliers
  where id = 'f4000000-0000-0000-0000-000000000003'
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete pemasok (1 baris)') from deleted;

-- ══════════════════════════════════════════════════════════════════════════
-- ISOLASI, FK, GUARD
-- ══════════════════════════════════════════════════════════════════════════
-- (25) owner A tidak melihat pelanggan tenant B
select is(
  count(*)::int, 0, 'OWNER A: tidak melihat pelanggan tenant B'
) from public.customers where tenant_id = 'f2000000-0000-0000-0000-000000000002';

-- (26) owner A tidak melihat pemasok tenant B
select is(
  count(*)::int, 0, 'OWNER A: tidak melihat pemasok tenant B'
) from public.suppliers where tenant_id = 'f2000000-0000-0000-0000-000000000002';

-- (27) owner A tidak bisa insert pelanggan ke tenant B
select throws_ok(
  $q$ insert into public.customers (tenant_id, name)
      values ('f2000000-0000-0000-0000-000000000002', 'Pelanggan Bajakan') $q$,
  '42501',
  'new row violates row-level security policy for table "customers"',
  'OWNER A: insert pelanggan tenant B ditolak'
);

-- (28) tier tenant B ditolak FK
select throws_ok(
  $q$ insert into public.customers (tenant_id, name, tier_id)
      values ('f2000000-0000-0000-0000-000000000001', 'Tier Nyasar',
              'f5000000-0000-0000-0000-000000000002') $q$,
  '23503',
  'insert or update on table "customers" violates foreign key constraint "customers_tier_same_tenant"',
  'OWNER A: tier tenant B ditolak'
);

-- (29) limit kredit negatif ditolak
select throws_ok(
  $q$ insert into public.customers (tenant_id, name, credit_limit)
      values ('f2000000-0000-0000-0000-000000000001', 'Limit Minus', -1) $q$,
  '23514',
  'new row for relation "customers" violates check constraint "customers_credit_limit_check"',
  'OWNER A: limit kredit negatif ditolak'
);

-- (30) tier yang dipakai pelanggan tidak bisa dihapus
select throws_ok(
  $q$ delete from public.price_tiers
      where tenant_id = 'f2000000-0000-0000-0000-000000000001' and name = 'Umum' $q$,
  '23503',
  'update or delete on table "price_tiers" violates foreign key constraint "customers_tier_same_tenant" on table "customers"',
  'OWNER A: tier yang dipakai pelanggan tidak bisa dihapus'
);

select * from finish();
rollback;
