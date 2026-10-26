-- Tes pgTAP 0015: penjualan (create_sale)
-- Idempotensi, stok, harga server, konversi satuan, RLS, piutang, audit.
begin;
select plan(45);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000001', 'authenticated', 'owner.sale@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.sale@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000003', 'authenticated', 'owner2.sale@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('a2000000-0000-0000-0000-000000000001', 'Tenant Sale A', 'bengkel'),
  ('a2000000-0000-0000-0000-000000000002', 'Tenant Sale B', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'owner'),
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'kasir'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000003', 'owner');

insert into public.outlets (id, tenant_id, name) values
  ('a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'Outlet A'),
  ('a3000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', 'Outlet B');

insert into public.units (id, tenant_id, name) values
  ('a4000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'pcs'),
  ('a4000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', 'sak'),
  ('a4000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000001', 'kg');

insert into public.products (id, tenant_id, name, sku, base_unit_id, kind, track_stock, sell_price, cost_price)
values
  ('a5000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001',
   'Semen Test', 'SEMEN-T', 'a4000000-0000-0000-0000-000000000001', 'barang', true, 10000, 7000),
  ('a5000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001',
   'Jasa Servis', 'JASA-T', 'a4000000-0000-0000-0000-000000000001', 'jasa', false, 50000, 0);

-- 1 sak = 40 pcs, harga jual sak Rp 360.000
insert into public.product_units (tenant_id, product_id, unit_id, factor_to_base, sell_price)
values ('a2000000-0000-0000-0000-000000000001',
        'a5000000-0000-0000-0000-000000000001',
        'a4000000-0000-0000-0000-000000000002', 40, 360000);

insert into public.customers (id, tenant_id, name, credit_limit)
values
  ('a6000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'Pelanggan Tanpa Limit', 0),
  ('a6000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', 'Pelanggan Limit Kecil', 15000);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note)
values ('a2000000-0000-0000-0000-000000000001',
        'a5000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001', 10, 'adjustment', 'Stok awal tes');

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

-- Helper: item JSON (array berisi satu item, sesuai input RPC)
create or replace function tests_item(
  p_product uuid, p_unit uuid, p_qty numeric, p_price bigint, p_discount bigint default 0
) returns jsonb
  language sql as $$
  select jsonb_build_array(jsonb_build_object(
    'product_id', p_product, 'unit_id', p_unit, 'qty', p_qty,
    'unit_price', p_price, 'discount', p_discount
  ));
  $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- (1) Kasir membuat penjualan tunai
-- ═══════════════════════════════════════════════════════════════════════════════
select tests_set_user('a1000000-0000-0000-0000-000000000002');
select lives_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 2, 10000),
        '[{"method":"tunai","amount":20000}]'::jsonb, null, 'Jual 2 pcs', null, null) $q$,
  'KASIR: penjualan tunai berhasil'
);

-- (2) Status paid + total server
select is(
  (select (status, total, paid_amount, change_amount)
     from public.sales
     where client_uuid = 'b1000000-0000-0000-0000-000000000001'),
  ('paid'::text, 20000::bigint, 20000::bigint, 0::bigint),
  'SALE: status paid, total 20000, kembalian 0'
);

-- (3) Snapshot harga + HPP di item
select is(
  (select (unit_price, unit_cost, line_total, qty_base)
     from public.sale_items
     where sale_id = (select id from public.sales
                      where client_uuid = 'b1000000-0000-0000-0000-000000000001')),
  (10000::bigint, 7000::bigint, 20000::bigint, 2::numeric),
  'ITEM: snapshot harga 10000, HPP 7000, total 20000'
);

-- (4) Movement sale tercatat
select is(
  (select (qty_base, unit_cost) from public.stock_movements
    where ref_type = 'sale'
      and ref_id = (select id from public.sales
                    where client_uuid = 'b1000000-0000-0000-0000-000000000001')),
  (-2::numeric, 7000::bigint),
  'MOVEMENT: qty -2 dengan unit_cost 7000'
);

-- (5) Stok berkurang 10 → 8
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'a2000000-0000-0000-0000-000000000001'
      and product_id = 'a5000000-0000-0000-0000-000000000001'
      and outlet_id = 'a3000000-0000-0000-0000-000000000001'),
  8::numeric, 'STOK: 10 - 2 = 8'
);

-- (6) Audit log tercatat
select is(
  (select count(*)::int from public.audit_logs
    where tenant_id = 'a2000000-0000-0000-0000-000000000001'
      and entity = 'sale'),
  1, 'AUDIT: 1 entri create sale'
);

-- (7) Idempoten: client_uuid sama
select lives_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 2, 10000),
        '[{"method":"tunai","amount":20000}]'::jsonb, null, null, null, null) $q$,
  'IDEMPOTEN: panggilan ulang tidak error'
);

-- (8) Tidak ada sale / movement dobel
select tests_set_postgres();
select is(
  (select count(*)::int from public.sales
    where client_uuid = 'b1000000-0000-0000-0000-000000000001'),
  1, 'VERIF: tetap 1 sale'
);
select is(
  (select count(*)::int from public.stock_movements
    where ref_type = 'sale'
      and ref_id = (select id from public.sales
                    where client_uuid = 'b1000000-0000-0000-0000-000000000001')),
  1, 'VERIF: movement tidak dobel'
);
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'a2000000-0000-0000-0000-000000000001'
      and product_id = 'a5000000-0000-0000-0000-000000000001'
      and outlet_id = 'a3000000-0000-0000-0000-000000000001'),
  8::numeric, 'VERIF: stok tetap 8 setelah panggilan ulang'
);

-- (9) Harga dikarang client ditolak
select tests_set_user('a1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000002',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 1, 9000),
        '[{"method":"tunai","amount":9000}]'::jsonb, null, null, null, null) $q$,
  'P0001',
  'Harga Semen Test tidak sesuai harga jual (seharusnya 10000)',
  'HARGA: harga karangan client ditolak'
);

-- (10) Stok tidak berubah setelah harga ditolak
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'a2000000-0000-0000-0000-000000000001'
      and product_id = 'a5000000-0000-0000-0000-000000000001'
      and outlet_id = 'a3000000-0000-0000-0000-000000000001'),
  8::numeric, 'VERIF: stok tetap 8 setelah harga ditolak'
);

-- (11) Stok tidak cukup ditolak
select tests_set_user('a1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000003',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 100, 10000),
        '[{"method":"tunai","amount":1000000}]'::jsonb, null, null, null, null) $q$,
  'P0001',
  'Stok Semen Test tidak cukup (tersedia 8, dibutuhkan 100)',
  'STOK: penjualan melebihi stok ditolak'
);

-- (12) Verifikasi stok tetap
select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'a2000000-0000-0000-0000-000000000001'
      and product_id = 'a5000000-0000-0000-0000-000000000001'
      and outlet_id = 'a3000000-0000-0000-0000-000000000001'),
  8::numeric, 'VERIF: stok tetap 8 setelah penjualan ditolak'
);

-- (13) Satuan tidak terdaftar ditolak
select tests_set_user('a1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000004',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000003', 1, 10000),
        '[{"method":"tunai","amount":10000}]'::jsonb, null, null, null, null) $q$,
  'P0001',
  'Satuan tidak terdaftar untuk produk Semen Test',
  'SATUAN: kg tidak terdaftar untuk produk ditolak'
);

-- (14) Pembayaran kurang tanpa pelanggan ditolak
select throws_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000005',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 1, 10000),
        '[{"method":"tunai","amount":5000}]'::jsonb, null, null, null, null) $q$,
  'P0001',
  'Pembayaran kurang dari total: wajib pilih pelanggan untuk kredit',
  'KREDIT: kurang bayar tanpa pelanggan ditolak'
);

-- (15) Kurang bayar dengan pelanggan → partial + piutang
select lives_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000006',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        'a6000000-0000-0000-0000-000000000001',
        public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 1, 10000),
        '[{"method":"tunai","amount":5000}]'::jsonb, null, null, null, null) $q$,
  'KREDIT: kurang bayar dengan pelanggan berhasil'
);

select tests_set_postgres();
select is(
  (select (status, paid_amount) from public.sales
    where client_uuid = 'b1000000-0000-0000-0000-000000000006'),
  ('partial'::text, 5000::bigint),
  'VERIF: status partial, paid 5000'
);
select is(
  (select amount from public.receivables
    where sale_id = (select id from public.sales
                     where client_uuid = 'b1000000-0000-0000-0000-000000000006')),
  5000::bigint, 'VERIF: piutang 5000'
);

-- (16) Bayar lebih → kembalian, paid_amount dibatasi total
select tests_set_user('a1000000-0000-0000-0000-000000000002');
select lives_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000007',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 2, 10000),
        '[{"method":"tunai","amount":50000}]'::jsonb, null, null, null, null) $q$,
  'TUNAI: bayar lebih berhasil'
);

select tests_set_postgres();
select is(
  (select (change_amount, paid_amount, total) from public.sales
    where client_uuid = 'b1000000-0000-0000-0000-000000000007'),
  (30000::bigint, 20000::bigint, 20000::bigint),
  'VERIF: kembalian 30000, paid dibatasi 20000'
);

-- (17) Konversi satuan: 0.1 sak = 4 pcs
select tests_set_user('a1000000-0000-0000-0000-000000000002');
select lives_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000008',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000002', 0.1, 360000),
        '[{"method":"tunai","amount":36000}]'::jsonb, null, null, null, null) $q$,
  'SATUAN: jual 0,1 sak berhasil'
);

select tests_set_postgres();
select is(
  (select (qty, qty_base, unit_price, line_total) from public.sale_items
    where sale_id = (select id from public.sales
                     where client_uuid = 'b1000000-0000-0000-0000-000000000008')),
  (0.1::numeric, 4::numeric, 360000::bigint, 36000::bigint),
  'VERIF: 0,1 sak = 4 pcs, total 36000'
);
select is(
  (select qty_base from public.stock_movements
    where ref_type = 'sale'
      and ref_id = (select id from public.sales
                    where client_uuid = 'b1000000-0000-0000-0000-000000000008')),
  (-4)::numeric, 'VERIF: movement -4 pcs'
);

-- (18) Jasa tidak membuat movement
select tests_set_user('a1000000-0000-0000-0000-000000000002');
select lives_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-000000000009',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000002',
          'a4000000-0000-0000-0000-000000000001', 1, 50000),
        '[{"method":"tunai","amount":50000}]'::jsonb, null, null, null, null) $q$,
  'JASA: penjualan jasa berhasil'
);

select tests_set_postgres();
select is(
  (select count(*)::int from public.stock_movements
    where ref_type = 'sale'
      and ref_id = (select id from public.sales
                    where client_uuid = 'b1000000-0000-0000-0000-000000000009')),
  0, 'VERIF: jasa tidak membuat movement'
);

-- (19) Multi-item: 2 item, 1 movement (tanpa bentrok client_uuid)
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'a2000000-0000-0000-0000-000000000001'
      and product_id = 'a5000000-0000-0000-0000-000000000001'
      and outlet_id = 'a3000000-0000-0000-0000-000000000001'),
  1::numeric, 'VERIF: stok setelah 2+1+2+4 = 1'
);

select tests_set_user('a1000000-0000-0000-0000-000000000002');
select lives_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-00000000000a',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null,
        public.tests_item('a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 1, 10000)
        || public.tests_item('a5000000-0000-0000-0000-000000000002',
          'a4000000-0000-0000-0000-000000000001', 1, 50000),
        '[{"method":"tunai","amount":60000}]'::jsonb, null, null, null, null) $q$,
  'MULTI: penjualan 2 item berhasil'
);

select tests_set_postgres();
select is(
  (select count(*)::int from public.sale_items
    where sale_id = (select id from public.sales
                     where client_uuid = 'b1000000-0000-0000-0000-00000000000a')),
  2, 'VERIF: 2 sale_items'
);
select is(
  (select count(*)::int from public.stock_movements
    where ref_type = 'sale'
      and ref_id = (select id from public.sales
                    where client_uuid = 'b1000000-0000-0000-0000-00000000000a')),
  1, 'VERIF: 1 movement untuk item ber-stok'
);

-- (20) Insert langsung ditolak untuk semua tabel transaksi
select tests_set_user('a1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ insert into public.sales
        (tenant_id, outlet_id, invoice_no, client_uuid, status, subtotal,
         total, paid_amount, cashier_id)
      values ('a2000000-0000-0000-0000-000000000001',
              'a3000000-0000-0000-0000-000000000001', 'INV-LANGSUNG',
              'b1000000-0000-0000-0000-0000000000fe', 'paid', 10000,
              10000, 10000, 'a1000000-0000-0000-0000-000000000002') $q$,
  '42501',
  'permission denied for table sales',
  'RLS: insert langsung ke sales ditolak'
);

select throws_ok(
  $q$ insert into public.payments (tenant_id, sale_id, method, amount)
      values ('a2000000-0000-0000-0000-000000000001',
              (select id from public.sales limit 1), 'tunai', 1000) $q$,
  '42501',
  'permission denied for table payments',
  'RLS: insert langsung ke payments ditolak'
);

select throws_ok(
  $q$ insert into public.sale_items
        (tenant_id, sale_id, product_id, unit_id, qty, qty_base,
         unit_price, line_total)
      values ('a2000000-0000-0000-0000-000000000001',
              (select id from public.sales limit 1),
              'a5000000-0000-0000-0000-000000000001',
              'a4000000-0000-0000-0000-000000000001', 1, 1, 10000, 10000) $q$,
  '42501',
  'permission denied for table sale_items',
  'RLS: insert langsung ke sale_items ditolak'
);

-- (21) Tenant B tidak melihat penjualan tenant A
select tests_set_user('a1000000-0000-0000-0000-000000000003');
select is(
  (select count(*)::int from public.sales),
  0, 'RLS: owner tenant B tidak melihat penjualan tenant A'
);

-- (22) Tenant B tidak bisa membuat penjualan di tenant A
select throws_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-00000000000b',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 1, 10000),
        '[{"method":"tunai","amount":10000}]'::jsonb, null, null, null, null) $q$,
  '42501',
  'Tidak berhak membuat penjualan',
  'RLS: tenant B tidak bisa menjual di tenant A'
);

-- (23) Format invoice + tidak ada nomor dobel
select tests_set_postgres();
select ok(
  (select bool_and(invoice_no ~ ('^INV-' || to_char(current_date, 'YYYYMMDD') || '-[0-9]{4}$'))
   from public.sales
   where tenant_id = 'a2000000-0000-0000-0000-000000000001'),
  'INVOICE: semua nomor berformat INV-YYYYMMDD-####'
);
select is(
  (select count(distinct invoice_no)::int from public.sales
    where tenant_id = 'a2000000-0000-0000-0000-000000000001'),
  (select count(*)::int from public.sales
    where tenant_id = 'a2000000-0000-0000-0000-000000000001'),
  'INVOICE: nomor unik per penjualan'
);

-- (24) tenant_id tidak bisa diubah
select throws_ok(
  $q$ update public.sales set tenant_id = 'a2000000-0000-0000-0000-000000000002'
      where client_uuid = 'b1000000-0000-0000-0000-000000000001' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel sales)',
  'DB: update tenant_id penjualan ditolak trigger'
);

-- (25) allow_negative_stock dihormati
update public.tenants
set settings = jsonb_build_object('allow_negative_stock', true)
where id = 'a2000000-0000-0000-0000-000000000001';

select tests_set_user('a1000000-0000-0000-0000-000000000002');
select lives_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-00000000000c',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000001',
          'a4000000-0000-0000-0000-000000000001', 100, 10000),
        '[{"method":"tunai","amount":1000000}]'::jsonb, null, null, null, null) $q$,
  'SETTING: allow_negative_stock=true mengizinkan stok minus'
);

select tests_set_postgres();
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'a2000000-0000-0000-0000-000000000001'
      and product_id = 'a5000000-0000-0000-0000-000000000001'
      and outlet_id = 'a3000000-0000-0000-0000-000000000001'),
  (-100)::numeric, 'VERIF: stok menjadi -100'
);

-- (26) Shift tertutup ditolak
insert into public.cash_shifts (
  id, tenant_id, outlet_id, cashier_id, opening_cash, client_uuid,
  closed_at, closing_cash_counted, expected_cash, difference
) values (
  'a7000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001',
  'a3000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000002', 0,
  'b1000000-0000-0000-0000-0000000000f1',
  now(), 0, 0, 0
);

select tests_set_user('a1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-00000000000d',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        null, public.tests_item(
          'a5000000-0000-0000-0000-000000000002',
          'a4000000-0000-0000-0000-000000000001', 1, 50000),
        '[{"method":"tunai","amount":50000}]'::jsonb,
        'a7000000-0000-0000-0000-000000000001', null, null, null) $q$,
  'P0001',
  'Shift sudah ditutup',
  'SHIFT: penjualan dengan shift tertutup ditolak'
);

-- (27) Pembayaran kredit_tempo tidak dihitung sebagai uang masuk
select lives_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-00000000000e',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        'a6000000-0000-0000-0000-000000000001',
        public.tests_item(
          'a5000000-0000-0000-0000-000000000002',
          'a4000000-0000-0000-0000-000000000001', 1, 50000),
        '[{"method":"kredit_tempo","amount":50000}]'::jsonb, null, null, null, null) $q$,
  'KREDIT: pembayaran kredit_tempo berhasil dicatat'
);

select tests_set_postgres();
select is(
  (select (status, paid_amount) from public.sales
    where client_uuid = 'b1000000-0000-0000-0000-00000000000e'),
  ('credit'::text, 0::bigint),
  'VERIF: kredit_tempo → status credit, paid 0'
);

-- (28) Limit kredit dilampaui ditolak
select tests_set_user('a1000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.create_sale(
        'b1000000-0000-0000-0000-00000000000f',
        'a2000000-0000-0000-0000-000000000001',
        'a3000000-0000-0000-0000-000000000001',
        'a6000000-0000-0000-0000-000000000002',
        public.tests_item(
          'a5000000-0000-0000-0000-000000000002',
          'a4000000-0000-0000-0000-000000000001', 1, 50000),
        '[{"method":"kredit_tempo","amount":50000}]'::jsonb, null, null, null, null) $q$,
  'P0001',
  'Melebihi limit kredit pelanggan (limit 15000, terpakai 0, tagihan 50000)',
  'KREDIT: melebihi limit kredit ditolak'
);

select tests_set_postgres();
select is(
  (select count(*)::int from public.sales
    where client_uuid = 'b1000000-0000-0000-0000-00000000000f'),
  0, 'VERIF: tidak ada sale saat limit kredit ditolak'
);

select * from finish();
rollback;
