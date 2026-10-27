-- Tes pgTAP 0020: outbox sync + needs_review
begin;
select plan(36);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000001', 'authenticated', 'owner.outbox@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.outbox@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000003', 'authenticated', 'owner2.outbox@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('f2000000-0000-0000-0000-000000000001', 'Tenant Outbox A', 'bengkel'),
  ('f2000000-0000-0000-0000-000000000002', 'Tenant Outbox B', 'bengkel');

insert into public.memberships (tenant_id, user_id, role) values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'owner'),
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000002', 'kasir'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000003', 'owner');

insert into public.outlets (id, tenant_id, name)
values ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Outlet Outbox');

insert into public.units (id, tenant_id, name)
values ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'pcs');

insert into public.products (id, tenant_id, name, base_unit_id, kind, track_stock, sell_price, cost_price)
values ('f5000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
        'Barang Outbox', 'f4000000-0000-0000-0000-000000000001', 'barang', true, 10000, 6000);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note)
values ('f2000000-0000-0000-0000-000000000001',
        'f5000000-0000-0000-0000-000000000001',
        'f3000000-0000-0000-0000-000000000001', 3, 'adjustment', 'Stok awal');

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

create or replace function tests_stock() returns numeric
  language sql as $$
    select coalesce(qty_base, 0)
    from public.stock_levels
    where tenant_id = 'f2000000-0000-0000-0000-000000000001'
      and product_id = 'f5000000-0000-0000-0000-000000000001'
      and outlet_id = 'f3000000-0000-0000-0000-000000000001';
  $$;

create or replace function tests_sale_status(p_client uuid) returns text
  language sql as $$
    select status from public.sales
    where tenant_id = 'f2000000-0000-0000-0000-000000000001'
      and client_uuid = p_client;
  $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- A. Konflik stok saat sinkron → needs_review, stok tidak dipotong
-- ═══════════════════════════════════════════════════════════════════════════════

select tests_set_user('f1000000-0000-0000-0000-000000000001');

select is(
  (public.sync_sale(
    'a1000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000001',
    null,
    jsonb_build_array(jsonb_build_object(
      'product_id', 'f5000000-0000-0000-0000-000000000001',
      'unit_id', 'f4000000-0000-0000-0000-000000000001',
      'qty', 5, 'unit_price', 10000, 'discount', 0)),
    '[{"method":"tunai","amount":50000}]'::jsonb,
    null, null, null, null, 'TMP-TEST-0001')
  ->> 'status'),
  'needs_review',
  'SYNC: stok kurang → needs_review (tidak ditolak)'
);

select ok(
  position('Stok' in (
    public.sync_sale(
      'a1000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000001',
      null,
      jsonb_build_array(jsonb_build_object(
        'product_id', 'f5000000-0000-0000-0000-000000000001',
        'unit_id', 'f4000000-0000-0000-0000-000000000001',
        'qty', 5, 'unit_price', 10000, 'discount', 0)),
      '[{"method":"tunai","amount":50000}]'::jsonb,
      null, null, null, null, 'TMP-TEST-0001')
    ->> 'needs_review_reason'
  )) > 0,
  'SYNC: alasan konflik stok tersimpan'
);

select tests_set_postgres();
select is(
  tests_sale_status('a1000000-0000-0000-0000-000000000001'),
  'needs_review',
  'VERIF: sale tersimpan berstatus needs_review'
);
select is(
  (select local_invoice_no from public.sales
    where client_uuid = 'a1000000-0000-0000-0000-000000000001'),
  'TMP-TEST-0001',
  'VERIF: nomor sementara perangkat tersimpan'
);
select is(tests_stock(), 3::numeric, 'VERIF: stok tidak dipotong');
select is(
  (select count(*) from public.stock_movements
    where tenant_id = 'f2000000-0000-0000-0000-000000000001'
      and type = 'sale'),
  0::bigint,
  'VERIF: tidak ada movement penjualan'
);

-- Idempotensi: kirim ulang tidak membuat sale kedua.
select tests_set_user('f1000000-0000-0000-0000-000000000001');
select is(
  (public.sync_sale(
    'a1000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000001',
    null,
    jsonb_build_array(jsonb_build_object(
      'product_id', 'f5000000-0000-0000-0000-000000000001',
      'unit_id', 'f4000000-0000-0000-0000-000000000001',
      'qty', 5, 'unit_price', 10000, 'discount', 0)),
    '[{"method":"tunai","amount":50000}]'::jsonb,
    null, null, null, null, 'TMP-TEST-0001')
  ->> 'status'),
  'needs_review',
  'SYNC: kirim ulang tetap needs_review'
);
select is(
  (public.sync_sale(
    'a1000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000001',
    null,
    jsonb_build_array(jsonb_build_object(
      'product_id', 'f5000000-0000-0000-0000-000000000001',
      'unit_id', 'f4000000-0000-0000-0000-000000000001',
      'qty', 5, 'unit_price', 10000, 'discount', 0)),
    '[{"method":"tunai","amount":50000}]'::jsonb,
    null, null, null, null, 'TMP-TEST-0001')
  ->> 'sale_id'),
  (select id::text from public.sales
    where client_uuid = 'a1000000-0000-0000-0000-000000000001'),
  'SYNC: idempoten, sale_id sama'
);

-- Online tetap ketat.
select throws_ok(
  $q$ select public.create_sale(
      'a1000000-0000-0000-0000-000000000002',
      'f2000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000001',
      null,
      jsonb_build_array(jsonb_build_object(
        'product_id', 'f5000000-0000-0000-0000-000000000001',
        'unit_id', 'f4000000-0000-0000-0000-000000000001',
        'qty', 5, 'unit_price', 10000, 'discount', 0)),
      '[{"method":"tunai","amount":50000}]'::jsonb,
      null, null, null, null) $q$,
  'P0001',
  'Stok Barang Outbox tidak cukup (tersedia 3, dibutuhkan 5)',
  'CREATE_SALE: stok kurang tetap ditolak saat online'
);

select tests_set_postgres();
select is(tests_stock(), 3::numeric, 'VERIF: stok tetap setelah penolakan online');

-- ═══════════════════════════════════════════════════════════════════════════════
-- B. Harga berubah saat offline → needs_review
-- ═══════════════════════════════════════════════════════════════════════════════

select tests_set_user('f1000000-0000-0000-0000-000000000001');
select is(
  (public.sync_sale(
    'a1000000-0000-0000-0000-000000000003',
    'f2000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000001',
    null,
    jsonb_build_array(jsonb_build_object(
      'product_id', 'f5000000-0000-0000-0000-000000000001',
      'unit_id', 'f4000000-0000-0000-0000-000000000001',
      'qty', 1, 'unit_price', 9000, 'discount', 0)),
    '[{"method":"tunai","amount":9000}]'::jsonb,
    null, null, null, null, 'TMP-TEST-0003')
  ->> 'status'),
  'needs_review',
  'SYNC: harga berbeda → needs_review'
);
select ok(
  position('Harga' in (
    select needs_review_reason from public.sales
    where client_uuid = 'a1000000-0000-0000-0000-000000000003'
  )) > 0,
  'SYNC: alasan harga tersimpan'
);
select is(tests_stock(), 3::numeric, 'VERIF: stok belum dipotong untuk harga');

-- ═══════════════════════════════════════════════════════════════════════════════
-- C. Hak akses & pengaman void
-- ═══════════════════════════════════════════════════════════════════════════════

select tests_set_user('f1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.resolve_sale_review(
      (select id from public.sales where client_uuid = 'a1000000-0000-0000-0000-000000000001'),
      'accept', null) $q$,
  '42501',
  'Tidak berhak menyelesaikan review',
  'KASIR: tidak boleh menyelesaikan review'
);

select tests_set_user('f1000000-0000-0000-0000-000000000003');
select throws_ok(
  $q$ select public.resolve_sale_review(
      (select id from public.sales where client_uuid = 'a1000000-0000-0000-0000-000000000001'),
      'accept', null) $q$,
  'P0001',
  'Penjualan tidak ditemukan',
  'TENANT LAIN: transaksi tenant lain tidak terlihat'
);

select tests_set_user('f1000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.void_sale(
      (select id from public.sales where client_uuid = 'a1000000-0000-0000-0000-000000000001'),
      'Salah input', 'a2000000-0000-0000-0000-000000000001') $q$,
  'P0001',
  'Transaksi berstatus perlu review: selesaikan lewat resolve_sale_review',
  'VOID: needs_review tidak bisa di-void biasa (cegah stok dobel)'
);

select tests_set_postgres();
select is(
  tests_sale_status('a1000000-0000-0000-0000-000000000001'),
  'needs_review',
  'VERIF: status tetap needs_review setelah void ditolak'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- D. Setujui review → stok dipotong + status final
-- ═══════════════════════════════════════════════════════════════════════════════

select tests_set_user('f1000000-0000-0000-0000-000000000001');
select is(
  (public.resolve_sale_review(
    (select id from public.sales where client_uuid = 'a1000000-0000-0000-0000-000000000003'),
    'accept', 'Harga sudah dicek') ->> 'status'),
  'paid',
  'REVIEW: setujui → status paid'
);

select tests_set_postgres();
select is(tests_stock(), 2::numeric, 'VERIF: stok dipotong setelah disetujui');
select is(
  (select count(*) from public.stock_movements
    where tenant_id = 'f2000000-0000-0000-0000-000000000001'
      and type = 'sale'),
  1::bigint,
  'VERIF: movement penjualan dibuat'
);
select ok(
  (select reviewed_at is not null from public.sales
    where client_uuid = 'a1000000-0000-0000-0000-000000000003'),
  'VERIF: reviewed_at terisi'
);
select ok(
  exists (
    select 1 from public.audit_logs
    where action = 'review_accept'
      and entity_id = (select id from public.sales
        where client_uuid = 'a1000000-0000-0000-0000-000000000003')
  ),
  'VERIF: audit review_accept tercatat'
);

select tests_set_user('f1000000-0000-0000-0000-000000000001');
select is(
  ((public.resolve_sale_review(
    (select id from public.sales where client_uuid = 'a1000000-0000-0000-0000-000000000003'),
    'accept', null) ->> 'idempotent'))::boolean,
  true,
  'REVIEW: setujui dua kali idempoten'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- E. Setujui saat stok masih kurang → ditolak, tetap needs_review
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (public.sync_sale(
    'a1000000-0000-0000-0000-000000000004',
    'f2000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000001',
    null,
    jsonb_build_array(jsonb_build_object(
      'product_id', 'f5000000-0000-0000-0000-000000000001',
      'unit_id', 'f4000000-0000-0000-0000-000000000001',
      'qty', 3, 'unit_price', 10000, 'discount', 0)),
    '[{"method":"tunai","amount":30000}]'::jsonb,
    null, null, null, null, 'TMP-TEST-0004')
  ->> 'status'),
  'needs_review',
  'SYNC: stok 2 < 3 → needs_review'
);

select throws_ok(
  $q$ select public.resolve_sale_review(
      (select id from public.sales where client_uuid = 'a1000000-0000-0000-0000-000000000004'),
      'accept', null) $q$,
  'P0001',
  'Stok Barang Outbox tidak cukup (tersedia 2, dibutuhkan 3). Sesuaikan stok dulu.',
  'REVIEW: setujui ditolak kalau stok masih kurang'
);

select tests_set_postgres();
select is(
  tests_sale_status('a1000000-0000-0000-0000-000000000004'),
  'needs_review',
  'VERIF: tetap needs_review'
);
select is(tests_stock(), 2::numeric, 'VERIF: stok tidak berubah');

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note)
values ('f2000000-0000-0000-0000-000000000001',
        'f5000000-0000-0000-0000-000000000001',
        'f3000000-0000-0000-0000-000000000001', 10, 'adjustment', 'Tambah stok');
select is(tests_stock(), 12::numeric, 'VERIF: stok setelah penyesuaian 12');

select tests_set_user('f1000000-0000-0000-0000-000000000001');
select is(
  (public.resolve_sale_review(
    (select id from public.sales where client_uuid = 'a1000000-0000-0000-0000-000000000004'),
    'accept', null) ->> 'status'),
  'paid',
  'REVIEW: setelah stok cukup → paid'
);

select tests_set_postgres();
select is(tests_stock(), 9::numeric, 'VERIF: stok 12 - 3 = 9');

-- ═══════════════════════════════════════════════════════════════════════════════
-- F. Batalkan review → void tanpa mengubah stok
-- ═══════════════════════════════════════════════════════════════════════════════

select tests_set_user('f1000000-0000-0000-0000-000000000001');
select is(
  (public.sync_sale(
    'a1000000-0000-0000-0000-000000000005',
    'f2000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000001',
    null,
    jsonb_build_array(jsonb_build_object(
      'product_id', 'f5000000-0000-0000-0000-000000000001',
      'unit_id', 'f4000000-0000-0000-0000-000000000001',
      'qty', 1, 'unit_price', 9000, 'discount', 0)),
    '[{"method":"tunai","amount":9000}]'::jsonb,
    null, null, null, null, 'TMP-TEST-0005')
  ->> 'status'),
  'needs_review',
  'SYNC: transaksi kelima butuh review'
);

select is(
  (public.resolve_sale_review(
    (select id from public.sales where client_uuid = 'a1000000-0000-0000-0000-000000000005'),
    'void', 'Pelanggan batal') ->> 'status'),
  'void',
  'REVIEW: batalkan → void'
);

select tests_set_postgres();
select is(tests_stock(), 9::numeric, 'VERIF: void tidak mengubah stok');
select is(
  (select count(*) from public.stock_movements
    where tenant_id = 'f2000000-0000-0000-0000-000000000001'
      and type = 'sale'),
  2::bigint,
  'VERIF: tidak ada movement tambahan untuk void'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- G. Batas fungsi internal
-- ═══════════════════════════════════════════════════════════════════════════════

select tests_set_user('f1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.sync_sale(
      'a1000000-0000-0000-0000-000000000006',
      'f2000000-0000-0000-0000-000000000002',
      'f3000000-0000-0000-0000-000000000001',
      null,
      '[]'::jsonb, '[]'::jsonb, null, null, null, null, 'TMP-TEST-0006') $q$,
  '42501',
  'Tidak berhak membuat penjualan',
  'TENANT LAIN: sync_sale ditolak'
);

select throws_ok(
  $q$ select public._sales_core(
      'a1000000-0000-0000-0000-000000000007',
      'f2000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-000000000001',
      null, '[]'::jsonb, '[]'::jsonb, null, null, null, null,
      true, 'TMP-TEST-0007') $q$,
  '42501',
  'permission denied for function _sales_core',
  'FUNGSI INTERNAL: _sales_core tidak bisa dipanggil client'
);

select * from finish();
rollback;
