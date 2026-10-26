-- Tes pgTAP 0009: konversi satuan, tier harga, harga grosir, resolve_price
begin;
select plan(36);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'e1000000-0000-0000-0000-000000000001', 'authenticated', 'owner.price@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'e1000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.price@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'e1000000-0000-0000-0000-000000000003', 'authenticated', 'owner2.price@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('e2000000-0000-0000-0000-000000000001', 'Tenant Harga A', 'bengkel'),
  ('e2000000-0000-0000-0000-000000000002', 'Tenant Harga B', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'owner'),
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 'kasir'),
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000003', 'owner');

insert into public.units (id, tenant_id, name) values
  ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'kg'),
  ('e4000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001', 'sak'),
  ('e4000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-000000000002', 'sak');

insert into public.categories (id, tenant_id, name) values
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'Material');

insert into public.products (id, tenant_id, name, category_id, base_unit_id, kind, sell_price)
values
  ('e5000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
   'Semen 40kg', 'e3000000-0000-0000-0000-000000000001',
   'e4000000-0000-0000-0000-000000000001', 'barang', 10000),
  ('e5000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000002',
   'Semen B', null, 'e4000000-0000-0000-0000-000000000003', 'barang', 9000);

insert into public.product_units (tenant_id, product_id, unit_id, factor_to_base, sell_price)
values ('e2000000-0000-0000-0000-000000000001',
        'e5000000-0000-0000-0000-000000000001',
        'e4000000-0000-0000-0000-000000000002', 40, 380000);

insert into public.product_prices (tenant_id, product_id, tier_id, unit_id, price)
values
  ('e2000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001',
   (select id from public.price_tiers where tenant_id = 'e2000000-0000-0000-0000-000000000001' and name = 'Umum'),
   'e4000000-0000-0000-0000-000000000002', 390000),
  ('e2000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001',
   (select id from public.price_tiers where tenant_id = 'e2000000-0000-0000-0000-000000000001' and name = 'Kontraktor'),
   'e4000000-0000-0000-0000-000000000002', 370000);

insert into public.price_breaks (tenant_id, product_id, unit_id, min_qty, price)
values
  ('e2000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001',
   'e4000000-0000-0000-0000-000000000002', 2, 360000),
  ('e2000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001',
   'e4000000-0000-0000-0000-000000000002', 5, 350000);

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

-- helper id tier
create or replace function tier_id(p_name text) returns uuid
  language sql stable as $$
  select id from public.price_tiers
  where tenant_id = 'e2000000-0000-0000-0000-000000000001' and name = p_name;
  $$;

-- ══════════════════════════════════════════════════════════════════════════
-- default tier & RLS
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('e1000000-0000-0000-0000-000000000001');

-- (1) tenant baru otomatis dapat 4 tier default
select is(
  count(*)::int, 4, 'TIER: tenant baru punya 4 tier default'
) from public.price_tiers
where tenant_id = 'e2000000-0000-0000-0000-000000000001';

-- (2) kasir melihat product_units
select tests_set_user('e1000000-0000-0000-0000-000000000002');
select is(
  count(*)::int, 1, 'KASIR: melihat 1 konversi satuan'
) from public.product_units;

-- (3) kasir tidak bisa insert konversi
select throws_ok(
  $q$ insert into public.product_units (tenant_id, product_id, unit_id, factor_to_base, sell_price)
      values ('e2000000-0000-0000-0000-000000000001',
              'e5000000-0000-0000-0000-000000000001',
              'e4000000-0000-0000-0000-000000000001', 1, 10000) $q$,
  '42501',
  'new row violates row-level security policy for table "product_units"',
  'KASIR: insert konversi ditolak'
);

-- (4) kasir tidak bisa update konversi
with updated as (
  update public.product_units set sell_price = 1
  where tenant_id = 'e2000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: update konversi (0 baris)') from updated;

-- (5) verifikasi harga konversi tidak berubah
select tests_set_postgres();
select is(
  (select sell_price from public.product_units
    where tenant_id = 'e2000000-0000-0000-0000-000000000001'
      and unit_id = 'e4000000-0000-0000-0000-000000000002'),
  380000::bigint, 'VERIF: harga sak tidak berubah'
);

-- (6) kasir tidak bisa delete konversi
select tests_set_user('e1000000-0000-0000-0000-000000000002');
with deleted as (
  delete from public.product_units
  where tenant_id = 'e2000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 0, 'KASIR: delete konversi (0 baris)') from deleted;

-- (7) verifikasi konversi masih ada
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: konversi sak masih ada'
) from public.product_units
where tenant_id = 'e2000000-0000-0000-0000-000000000001';

-- ══════════════════════════════════════════════════════════════════════════
-- OWNER CRUD konversi, tier, harga tier, break
-- ══════════════════════════════════════════════════════════════════════════
select tests_set_user('e1000000-0000-0000-0000-000000000001');

-- (8) owner insert konversi dus
with inserted as (
  insert into public.product_units (tenant_id, product_id, unit_id, factor_to_base, sell_price)
  values ('e2000000-0000-0000-0000-000000000001',
          'e5000000-0000-0000-0000-000000000001',
          'e4000000-0000-0000-0000-000000000001', 1, 11000)
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert konversi (1 baris)') from inserted;

-- (9) owner update konversi
with updated as (
  update public.product_units set sell_price = 10500
  where tenant_id = 'e2000000-0000-0000-0000-000000000001'
    and unit_id = 'e4000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 1, 'OWNER: update konversi (1 baris)') from updated;

-- (10) verifikasi harga konversi
select tests_set_postgres();
select is(
  (select sell_price from public.product_units
    where tenant_id = 'e2000000-0000-0000-0000-000000000001'
      and unit_id = 'e4000000-0000-0000-0000-000000000001'),
  10500::bigint, 'VERIF: harga konversi berubah'
);

-- (11) owner delete konversi
select tests_set_user('e1000000-0000-0000-0000-000000000001');
with deleted as (
  delete from public.product_units
  where tenant_id = 'e2000000-0000-0000-0000-000000000001'
    and unit_id = 'e4000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete konversi (1 baris)') from deleted;

-- (12) verifikasi konversi hilang
select tests_set_postgres();
select is(
  count(*)::int, 0, 'VERIF: konversi tambahan sudah hilang'
) from public.product_units
where tenant_id = 'e2000000-0000-0000-0000-000000000001'
  and unit_id = 'e4000000-0000-0000-0000-000000000001';

-- (13) kasir tidak bisa insert tier
select tests_set_user('e1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ insert into public.price_tiers (tenant_id, name)
      values ('e2000000-0000-0000-0000-000000000001', 'Grosir') $q$,
  '42501',
  'new row violates row-level security policy for table "price_tiers"',
  'KASIR: insert tier ditolak'
);

-- (14) owner insert tier
select tests_set_user('e1000000-0000-0000-0000-000000000001');
with inserted as (
  insert into public.price_tiers (tenant_id, name)
  values ('e2000000-0000-0000-0000-000000000001', 'Grosir')
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert tier (1 baris)') from inserted;

-- (15) owner delete tier
with deleted as (
  delete from public.price_tiers
  where tenant_id = 'e2000000-0000-0000-0000-000000000001'
    and name = 'Grosir'
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete tier (1 baris)') from deleted;

-- (16) kasir tidak bisa insert harga tier
select tests_set_user('e1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ insert into public.product_prices (tenant_id, product_id, tier_id, unit_id, price)
      values ('e2000000-0000-0000-0000-000000000001',
              'e5000000-0000-0000-0000-000000000001',
              (select id from public.price_tiers
                where tenant_id = 'e2000000-0000-0000-0000-000000000001' and name = 'Umum'),
              'e4000000-0000-0000-0000-000000000002', 1) $q$,
  '42501',
  'new row violates row-level security policy for table "product_prices"',
  'KASIR: insert harga tier ditolak'
);

-- (17) owner insert harga tier Langganan
select tests_set_user('e1000000-0000-0000-0000-000000000001');
with inserted as (
  insert into public.product_prices (tenant_id, product_id, tier_id, unit_id, price)
  values ('e2000000-0000-0000-0000-000000000001',
          'e5000000-0000-0000-0000-000000000001',
          (select id from public.price_tiers
            where tenant_id = 'e2000000-0000-0000-0000-000000000001' and name = 'Langganan'),
          'e4000000-0000-0000-0000-000000000002', 375000)
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert harga tier (1 baris)') from inserted;

-- (18) owner update harga tier
with updated as (
  update public.product_prices set price = 365000
  where tenant_id = 'e2000000-0000-0000-0000-000000000001'
    and tier_id = (select id from public.price_tiers
                    where tenant_id = 'e2000000-0000-0000-0000-000000000001' and name = 'Langganan')
  returning id
)
select is(count(*)::int, 1, 'OWNER: update harga tier (1 baris)') from updated;

-- (19) verifikasi harga tier
select tests_set_postgres();
select is(
  (select price from public.product_prices
    where tenant_id = 'e2000000-0000-0000-0000-000000000001'
      and tier_id = (select id from public.price_tiers
                      where tenant_id = 'e2000000-0000-0000-0000-000000000001' and name = 'Langganan')),
  365000::bigint, 'VERIF: harga tier berubah'
);

-- (20) owner delete harga tier
select tests_set_user('e1000000-0000-0000-0000-000000000001');
with deleted as (
  delete from public.product_prices
  where tenant_id = 'e2000000-0000-0000-0000-000000000001'
    and tier_id = (select id from public.price_tiers
                    where tenant_id = 'e2000000-0000-0000-0000-000000000001' and name = 'Langganan')
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete harga tier (1 baris)') from deleted;

-- (21) kasir tidak bisa insert harga grosir
select tests_set_user('e1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ insert into public.price_breaks (tenant_id, product_id, unit_id, min_qty, price)
      values ('e2000000-0000-0000-0000-000000000001',
              'e5000000-0000-0000-0000-000000000001',
              'e4000000-0000-0000-0000-000000000002', 10, 1) $q$,
  '42501',
  'new row violates row-level security policy for table "price_breaks"',
  'KASIR: insert harga grosir ditolak'
);

-- (22) owner insert harga grosir
select tests_set_user('e1000000-0000-0000-0000-000000000001');
with inserted as (
  insert into public.price_breaks (id, tenant_id, product_id, unit_id, min_qty, price)
  values ('e6000000-0000-0000-0000-000000000001',
          'e2000000-0000-0000-0000-000000000001',
          'e5000000-0000-0000-0000-000000000001',
          'e4000000-0000-0000-0000-000000000002', 10, 340000)
  returning id
)
select is(count(*)::int, 1, 'OWNER: insert harga grosir (1 baris)') from inserted;

-- (23) owner update harga grosir
with updated as (
  update public.price_breaks set price = 330000
  where id = 'e6000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 1, 'OWNER: update harga grosir (1 baris)') from updated;

-- (24) verifikasi harga grosir
select tests_set_postgres();
select is(
  (select price from public.price_breaks
    where id = 'e6000000-0000-0000-0000-000000000001'),
  330000::bigint, 'VERIF: harga grosir berubah'
);

-- (25) owner delete harga grosir
select tests_set_user('e1000000-0000-0000-0000-000000000001');
with deleted as (
  delete from public.price_breaks
  where id = 'e6000000-0000-0000-0000-000000000001'
  returning id
)
select is(count(*)::int, 1, 'OWNER: delete harga grosir (1 baris)') from deleted;

-- ══════════════════════════════════════════════════════════════════════════
-- Isolasi & guard
-- ══════════════════════════════════════════════════════════════════════════
-- (26) owner tenant B tidak melihat konversi tenant A
select tests_set_user('e1000000-0000-0000-0000-000000000003');
select is(
  count(*)::int, 0, 'OWNER B: tidak melihat konversi tenant A'
) from public.product_units;

-- (27) owner tenant B tidak bisa insert konversi tenant A
select throws_ok(
  $q$ insert into public.product_units (tenant_id, product_id, unit_id, factor_to_base, sell_price)
      values ('e2000000-0000-0000-0000-000000000001',
              'e5000000-0000-0000-0000-000000000001',
              'e4000000-0000-0000-0000-000000000002', 1, 1) $q$,
  '42501',
  'new row violates row-level security policy for table "product_units"',
  'OWNER B: insert konversi tenant A ditolak'
);

-- (28) tenant_id tidak bisa dipindah
select tests_set_user('e1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ update public.product_units set tenant_id = 'e2000000-0000-0000-0000-000000000002'
      where tenant_id = 'e2000000-0000-0000-0000-000000000001' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel product_units)',
  'OWNER A: pindah tenant_id konversi ditolak trigger'
);

-- ══════════════════════════════════════════════════════════════════════════
-- resolve_price
-- ══════════════════════════════════════════════════════════════════════════
-- (29) harga base
select is(
  public.resolve_price(
    'e2000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    'e4000000-0000-0000-0000-000000000001',
    null, 1),
  10000::bigint, 'HARGA: base kg = 10.000'
);

-- (30) harga sak tier Umum
select is(
  public.resolve_price(
    'e2000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    'e4000000-0000-0000-0000-000000000002',
    tier_id('Umum'), 1),
  390000::bigint, 'HARGA: sak Umum = 390.000'
);

-- (31) harga sak tier Kontraktor
select is(
  public.resolve_price(
    'e2000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    'e4000000-0000-0000-0000-000000000002',
    tier_id('Kontraktor'), 1),
  370000::bigint, 'HARGA: sak Kontraktor = 370.000'
);

-- (32) qty 2 kena grosir 360.000
select is(
  public.resolve_price(
    'e2000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    'e4000000-0000-0000-0000-000000000002',
    tier_id('Kontraktor'), 2),
  360000::bigint, 'HARGA: qty 2 = 360.000'
);

-- (33) qty 5 kena grosir 350.000
select is(
  public.resolve_price(
    'e2000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    'e4000000-0000-0000-0000-000000000002',
    tier_id('Kontraktor'), 5),
  350000::bigint, 'HARGA: qty 5 = 350.000'
);

-- (34) tanpa tier pakai harga satuan tambahan
select is(
  public.resolve_price(
    'e2000000-0000-0000-0000-000000000001',
    'e5000000-0000-0000-0000-000000000001',
    'e4000000-0000-0000-0000-000000000002',
    null, 1),
  380000::bigint, 'HARGA: tanpa tier = harga sak 380.000'
);

-- (35) qty 0 ditolak
select throws_ok(
  $q$ select public.resolve_price(
        'e2000000-0000-0000-0000-000000000001',
        'e5000000-0000-0000-0000-000000000001',
        'e4000000-0000-0000-0000-000000000001', null, 0) $q$,
  'P0001',
  'qty harus lebih dari 0',
  'HARGA: qty 0 ditolak'
);

-- (36) user tenant B tidak boleh menghitung harga tenant A
select tests_set_user('e1000000-0000-0000-0000-000000000003');
select throws_ok(
  $q$ select public.resolve_price(
        'e2000000-0000-0000-0000-000000000001',
        'e5000000-0000-0000-0000-000000000001',
        'e4000000-0000-0000-0000-000000000002', null, 1) $q$,
  '42501',
  'Tidak berhak membaca harga tenant ini',
  'HARGA: non-member ditolak'
);

select * from finish();
rollback;
