-- Tes pgTAP 0023: penerimaan barang (T6.2)
-- Posting GR → movement 'purchase' + HPP rata-rata bergerak. Tulis hanya via RPC.
begin;
select plan(15);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000031', 'authenticated', 'owner.gr@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000032', 'authenticated', 'kasir.gr@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000033', 'authenticated', 'admin.gr@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000034', 'authenticated', 'owner2.gr@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('f2000000-0000-0000-0000-000000000031', 'Tenant GR A', 'toko_bangunan'),
  ('f2000000-0000-0000-0000-000000000032', 'Tenant GR B', 'toko_bangunan');

insert into public.outlets (id, tenant_id, name) values
  ('f3000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'Gudang A'),
  ('f3000000-0000-0000-0000-000000000032', 'f2000000-0000-0000-0000-000000000032', 'Gudang B');

insert into public.memberships (tenant_id, user_id, role) values
  ('f2000000-0000-0000-0000-000000000031', 'f1000000-0000-0000-0000-000000000031', 'owner'),
  ('f2000000-0000-0000-0000-000000000031', 'f1000000-0000-0000-0000-000000000032', 'kasir'),
  ('f2000000-0000-0000-0000-000000000031', 'f1000000-0000-0000-0000-000000000033', 'admin'),
  ('f2000000-0000-0000-0000-000000000032', 'f1000000-0000-0000-0000-000000000034', 'owner');

insert into public.suppliers (id, tenant_id, name, phone, payment_terms_days) values
  ('f4000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'Supplier A', '0821', 14),
  ('f4000000-0000-0000-0000-000000000032', 'f2000000-0000-0000-0000-000000000032', 'Supplier B', '0822', 0);

insert into public.units (id, tenant_id, name) values
  ('f5000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'pcs'),
  ('f5000000-0000-0000-0000-000000000032', 'f2000000-0000-0000-0000-000000000031', 'sak');

insert into public.categories (id, tenant_id, name) values
  ('f6000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'Bahan Bangunan');

insert into public.products (id, tenant_id, sku, barcode, name, category_id, kind, base_unit_id, track_stock, cost_price, sell_price, min_stock, active) values
  ('f7000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'SKU-001', '111', 'Semen', 'f6000000-0000-0000-0000-000000000031', 'barang', 'f5000000-0000-0000-0000-000000000031', true, 50000, 70000, 10, true),
  ('f7000000-0000-0000-0000-000000000032', 'f2000000-0000-0000-0000-000000000031', 'SKU-002', '222', 'Cat', 'f6000000-0000-0000-0000-000000000031', 'barang', 'f5000000-0000-0000-0000-000000000031', false, 0, 50000, 0, true);

insert into public.product_units (id, tenant_id, product_id, unit_id, factor_to_base, sell_price, barcode) values
  ('f8000000-0000-0000-0000-000000000031', 'f2000000-0000-0000-0000-000000000031', 'f7000000-0000-0000-0000-000000000031', 'f5000000-0000-0000-0000-000000000032', 40, 2500000, '999');

-- Stok awal produk Semen: 10 pcs @ cost 50000 (via movement sebagai postgres).
insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, unit_cost, note)
values
  ('f2000000-0000-0000-0000-000000000031', 'f7000000-0000-0000-0000-000000000031',
   'f3000000-0000-0000-0000-000000000031', 10, 'adjustment', 50000, 'Stok awal');

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
-- KASIR: baca boleh, terima barang ditolak
-- ═══════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000032');

select is(count(*)::int, 0, 'KASIR: melihat 0 GR') from public.goods_receipts;

select throws_ok(
  $q$ select public.receive_goods(
    '00000000-0000-0000-0000-000000000001'::uuid,
    'f2000000-0000-0000-0000-000000000031'::uuid,
    'f3000000-0000-0000-0000-000000000031'::uuid,
    'f4000000-0000-0000-0000-000000000031'::uuid,
    null,
    '[{"product_id":"f7000000-0000-0000-0000-000000000031","unit_id":"f5000000-0000-0000-0000-000000000031","qty":5,"unit_cost":70000}]'::jsonb,
    null
  ) $q$,
  '42501',
  'Hanya owner/admin yang boleh menerima barang',
  'KASIR: receive barang via RPC ditolak'
);

select tests_set_postgres();
select is(count(*)::int, 0, 'VERIF: GR tetap 0') from public.goods_receipts;

-- ═══════════════════════════════════════════════════════════════════════════
-- OWNER: terima barang, HPP rata-rata bergerak, idempoten
-- Stok awal 10 @ 50000. Terima 5 pcs @ 70000 → HPP = (10*50000+5*70000)/15 = 56667.
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000031');

with created as (
  select public.receive_goods(
    '00000000-0000-0000-0000-000000000002'::uuid,
    'f2000000-0000-0000-0000-000000000031'::uuid,
    'f3000000-0000-0000-0000-000000000031'::uuid,
    'f4000000-0000-0000-0000-000000000031'::uuid,
    null,
    '[{"product_id":"f7000000-0000-0000-0000-000000000031","unit_id":"f5000000-0000-0000-0000-000000000031","qty":5,"unit_cost":70000}]'::jsonb,
    'Contoh GR'
  ) as result
)
select is((result ->> 'idempotent')::boolean, false, 'OWNER: terima barang (idempotent false)') from created;

select tests_set_postgres();
select is(
  (select total from public.goods_receipts where gr_no like 'GR-%'),
  350000::bigint, 'VERIF: total GR = 5*70000 = 350000'
);

-- HPP rata-rata bergerak.
select is(
  (select cost_price from public.products where id = 'f7000000-0000-0000-0000-000000000031'),
  56667::bigint, 'VERIF: HPP baru = (10*50000+5*70000)/15 = 56667'
);

-- Stok bertambah: 10 + 5 = 15.
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'f2000000-0000-0000-0000-000000000031'
      and product_id = 'f7000000-0000-0000-0000-000000000031'
      and outlet_id = 'f3000000-0000-0000-0000-000000000031'),
  15::numeric, 'VERIF: stok 10 + 5 = 15'
);

-- Movement purchase tersimpan (hanya 1, stok awal adalah adjustment).
select is(
  count(*)::int, 1, 'VERIF: 1 movement pembelian (type purchase)'
) from public.stock_movements
where tenant_id = 'f2000000-0000-0000-0000-000000000031'
  and product_id = 'f7000000-0000-0000-0000-000000000031'
  and type = 'purchase';

-- Idempotensi: client_uuid sama → idempotent true, tidak duplikat.
select tests_set_user('f1000000-0000-0000-0000-000000000031');
with second as (
  select (public.receive_goods(
    '00000000-0000-0000-0000-000000000002'::uuid,
    'f2000000-0000-0000-0000-000000000031'::uuid,
    'f3000000-0000-0000-0000-000000000031'::uuid,
    'f4000000-0000-0000-0000-000000000031'::uuid,
    null,
    '[{"product_id":"f7000000-0000-0000-0000-000000000031","unit_id":"f5000000-0000-0000-0000-000000000031","qty":5,"unit_cost":70000}]'::jsonb,
    null
  ) ->> 'idempotent')::boolean as idem
)
select is(count(*)::int, 1, 'OWNER: client_uuid sama -> idempotent true') from second where idem;

select tests_set_postgres();
select is(count(*)::int, 1, 'VERIF: GR tetap 1 baris') from public.goods_receipts;

-- Stok tetap 15 (idempotensi tidak menambah stok).
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'f2000000-0000-0000-0000-000000000031'
      and product_id = 'f7000000-0000-0000-0000-000000000031'
      and outlet_id = 'f3000000-0000-0000-0000-000000000031'),
  15::numeric, 'VERIF: stok tetap 15 (idempotensi)'
);

-- ═══════════════════════════════════════════════════════════════════════════
-- ISOLASI: owner A tidak boleh terima barang di tenant B via RPC
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000031');
select throws_ok(
  $q$ select public.receive_goods(
    '00000000-0000-0000-0000-000000000003'::uuid,
    'f2000000-0000-0000-0000-000000000032'::uuid,
    'f3000000-0000-0000-0000-000000000032'::uuid,
    'f4000000-0000-0000-0000-000000000032'::uuid,
    null,
    '[{"product_id":"f7000000-0000-0000-0000-000000000031","unit_id":"f5000000-0000-0000-0000-000000000031","qty":1,"unit_cost":70000}]'::jsonb,
    null
  ) $q$,
  '42501',
  'Hanya owner/admin yang boleh menerima barang',
  'OWNER A: terima barang tenant B via RPC ditolak'
);

select is(
  count(*)::int, 0, 'OWNER A: tidak melihat GR tenant B'
) from public.goods_receipts where tenant_id = 'f2000000-0000-0000-0000-000000000032';

-- ════════════════════════════════════════════════════════════════════════════
-- CHECK: total negatif ditolak (via postgres; API privilege ditolak lebih dulu)
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_postgres();
select throws_ok(
  $q$ insert into public.goods_receipts (tenant_id, outlet_id, gr_no, client_uuid, supplier_id, status, total)
      values ('f2000000-0000-0000-0000-000000000031', 'f3000000-0000-0000-0000-000000000031', 'GR-NEG', '00000000-0000-0000-0000-000000000004'::uuid, 'f4000000-0000-0000-0000-000000000031'::uuid, 'received', -1000) $q$,
  '23514',
  'new row for relation "goods_receipts" violates check constraint "goods_receipts_total_check"',
  'OWNER A: total negatif ditolak'
);

select is(
  count(*)::int, 0, 'VERIF: GR total negatif tidak tersimpan'
) from public.goods_receipts where gr_no = 'GR-NEG';

select * from finish();
rollback;
