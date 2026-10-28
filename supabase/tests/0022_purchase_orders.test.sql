-- Tes pgTAP 0022: purchase_orders (T6.1)
-- Pola konsisten dengan create_sale: tulis tabel hanya lewat RPC security
-- definer, langsung di tabel dilarang (privilege direvoked).
begin;
select plan(12);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000021', 'authenticated', 'owner.po2@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000022', 'authenticated', 'kasir.po2@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000023', 'authenticated', 'admin.po2@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000024', 'authenticated', 'owner2.po2@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('f2000000-0000-0000-0000-000000000021', 'Tenant PO A', 'toko_bangunan'),
  ('f2000000-0000-0000-0000-000000000022', 'Tenant PO B', 'toko_bangunan');

insert into public.outlets (id, tenant_id, name) values
  ('f3000000-0000-0000-0000-000000000021', 'f2000000-0000-0000-0000-000000000021', 'Gudang A'),
  ('f3000000-0000-0000-0000-000000000022', 'f2000000-0000-0000-0000-000000000022', 'Gudang B');

insert into public.memberships (tenant_id, user_id, role) values
  ('f2000000-0000-0000-0000-000000000021', 'f1000000-0000-0000-0000-000000000021', 'owner'),
  ('f2000000-0000-0000-0000-000000000021', 'f1000000-0000-0000-0000-000000000022', 'kasir'),
  ('f2000000-0000-0000-0000-000000000021', 'f1000000-0000-0000-0000-000000000023', 'admin'),
  ('f2000000-0000-0000-0000-000000000022', 'f1000000-0000-0000-0000-000000000024', 'owner');

insert into public.suppliers (id, tenant_id, name, phone, payment_terms_days) values
  ('f4000000-0000-0000-0000-000000000021', 'f2000000-0000-0000-0000-000000000021', 'Supplier A', '0821', 14),
  ('f4000000-0000-0000-0000-000000000022', 'f2000000-0000-0000-0000-000000000022', 'Supplier B', '0822', 0);

insert into public.units (id, tenant_id, name) values
  ('f5000000-0000-0000-0000-000000000021', 'f2000000-0000-0000-0000-000000000021', 'pcs'),
  ('f5000000-0000-0000-0000-000000000022', 'f2000000-0000-0000-0000-000000000021', 'sak');

insert into public.categories (id, tenant_id, name) values
  ('f6000000-0000-0000-0000-000000000021', 'f2000000-0000-0000-0000-000000000021', 'Bahan Bangunan');

insert into public.products (id, tenant_id, sku, barcode, name, category_id, kind, base_unit_id, track_stock, cost_price, sell_price, min_stock, active) values
  ('f7000000-0000-0000-0000-000000000021', 'f2000000-0000-0000-0000-000000000021', 'SKU-001', '111', 'Semen', 'f6000000-0000-0000-0000-000000000021', 'barang', 'f5000000-0000-0000-0000-000000000021', true, 50000, 70000, 10, true),
  ('f7000000-0000-0000-0000-000000000022', 'f2000000-0000-0000-0000-000000000021', 'SKU-002', '222', 'Cat', 'f6000000-0000-0000-0000-000000000021', 'barang', 'f5000000-0000-0000-0000-000000000021', false, 0, 50000, 0, true);

insert into public.product_units (id, tenant_id, product_id, unit_id, factor_to_base, sell_price, barcode) values
  ('f8000000-0000-0000-0000-000000000021', 'f2000000-0000-0000-0000-000000000021', 'f7000000-0000-0000-0000-000000000021', 'f5000000-0000-0000-0000-000000000022', 40, 2500000, '999');

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
-- KASIR: baca boleh, buat PO ditolak
-- ═══════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000022');

-- (1) kasir melihat PO (belum ada)
select is(count(*)::int, 0, 'KASIR: melihat 0 PO') from public.purchase_orders;

-- (2) kasir tidak bisa buat PO via RPC
select throws_ok(
  $q$ select public.create_purchase_order(
    '00000000-0000-0000-0000-000000000001'::uuid,
    'f2000000-0000-0000-0000-000000000021'::uuid,
    'f3000000-0000-0000-0000-000000000021'::uuid,
    'f4000000-0000-0000-0000-000000000021'::uuid,
    '[{"product_id":"f7000000-0000-0000-0000-000000000021","unit_id":"f5000000-0000-0000-0000-000000000021","qty":5,"unit_price":70000}]'::jsonb,
    null
  ) $q$,
  '42501',
  'Hanya owner/admin yang boleh membuat PO',
  'KASIR: buat PO via RPC ditolak'
);

-- (3) verifikasi PO tetap 0
select tests_set_postgres();
select is(count(*)::int, 0, 'VERIF: PO tetap 0') from public.purchase_orders;

-- ═══════════════════════════════════════════════════════════════════════════
-- OWNER: buat PO draft, total dihitung server, idempoten
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000021');

-- (4) owner buat PO (2 item: 5 pcs @70000 + 1 sak @2500000 = 2.850.000)
with created as (
  select public.create_purchase_order(
    '00000000-0000-0000-0000-000000000002'::uuid,
    'f2000000-0000-0000-0000-000000000021'::uuid,
    'f3000000-0000-0000-0000-000000000021'::uuid,
    'f4000000-0000-0000-0000-000000000021'::uuid,
    '[{"product_id":"f7000000-0000-0000-0000-000000000021","unit_id":"f5000000-0000-0000-0000-000000000021","qty":5,"unit_price":70000},{"product_id":"f7000000-0000-0000-0000-000000000021","unit_id":"f5000000-0000-0000-0000-000000000022","qty":1,"unit_price":2500000}]'::jsonb,
    'Contoh PO'
  ) as result
)
select is((result ->> 'idempotent')::boolean, false, 'OWNER: buat PO (idempotent false)') from created;

-- (5) verifikasi total dihitung server
select tests_set_postgres();
select is(
  (select total from public.purchase_orders where po_no like 'PO-%'),
  2850000::bigint, 'VERIF: total PO = 5*70000 + 1*2500000 = 2.850.000'
);

-- (6) idempotensi: client_uuid sama -> idempotent true, tidak duplikat
select tests_set_user('f1000000-0000-0000-0000-000000000021');
with second as (
  select (public.create_purchase_order(
    '00000000-0000-0000-0000-000000000002'::uuid,
    'f2000000-0000-0000-0000-000000000021'::uuid,
    'f3000000-0000-0000-0000-000000000021'::uuid,
    'f4000000-0000-0000-0000-000000000021'::uuid,
    '[{"product_id":"f7000000-0000-0000-0000-000000000021","unit_id":"f5000000-0000-0000-0000-000000000021","qty":5,"unit_price":70000}]'::jsonb,
    null
  ) ->> 'idempotent')::boolean as idem
)
select is(count(*)::int, 1, 'OWNER: client_uuid sama -> idempotent true') from second where idem;

-- (7) verifikasi PO tetap 1 baris
select tests_set_postgres();
select is(count(*)::int, 1, 'VERIF: PO tetap 1 baris') from public.purchase_orders;

-- ═══════════════════════════════════════════════════════════════════════════
-- ISOLASI: owner A tidak boleh buat PO di tenant B (via RPC)
-- ════════════════════════════════════════════════════════════════════════════
select tests_set_user('f1000000-0000-0000-0000-000000000021');
select throws_ok(
  $q$ select public.create_purchase_order(
    '00000000-0000-0000-0000-000000000003'::uuid,
    'f2000000-0000-0000-0000-000000000022'::uuid,
    'f3000000-0000-0000-0000-000000000022'::uuid,
    'f4000000-0000-0000-0000-000000000022'::uuid,
    '[{"product_id":"f7000000-0000-0000-0000-000000000021","unit_id":"f5000000-0000-0000-0000-000000000021","qty":1,"unit_price":70000}]'::jsonb,
    null
  ) $q$,
  '42501',
  'Hanya owner/admin yang boleh membuat PO',
  'OWNER A: buat PO tenant B via RPC ditolak'
);

-- (9) owner A tidak melihat PO tenant B
select is(
  count(*)::int, 0, 'OWNER A: tidak melihat PO tenant B'
) from public.purchase_orders where tenant_id = 'f2000000-0000-0000-0000-000000000022';

-- (10) verifikasi item PO tenant A = 2 (dari satu PO di atas)
select tests_set_postgres();
select is(
  count(*)::int, 2, 'VERIF: item PO tenant A = 2'
) from public.purchase_order_items where tenant_id = 'f2000000-0000-0000-0000-000000000021';

-- ════════════════════════════════════════════════════════════════════════════
-- CHECK
-- ═════════════════════════════════════════════════════════════════════════════
-- (11) total negatif ditolak check constraint
select throws_ok(
  $q$ insert into public.purchase_orders (tenant_id, outlet_id, po_no, client_uuid, supplier_id, status, total)
      values ('f2000000-0000-0000-0000-000000000021', 'f3000000-0000-0000-0000-000000000021', 'PO-NEG', '00000000-0000-0000-0000-000000000004'::uuid, 'f4000000-0000-0000-0000-000000000021'::uuid, 'draft', -1000) $q$,
  '23514',
  'new row for relation "purchase_orders" violates check constraint "purchase_orders_total_check"',
  'OWNER A: total negatif ditolak'
);

-- (12) verifikasi PO total negatif tidak tersimpan
select tests_set_postgres();
select is(
  count(*)::int, 0, 'VERIF: PO total negatif tidak tersimpan'
) from public.purchase_orders where po_no = 'PO-NEG';

select * from finish();
rollback;
