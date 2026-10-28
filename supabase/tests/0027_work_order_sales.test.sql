-- Tes pgTAP 0027: konversi work order menjadi penjualan (T7.3)
begin;
select plan(23);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000041', 'authenticated', 'owner.wo.sale@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-000000000042', 'authenticated', 'kasir.wo.sale@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('f2000000-0000-0000-0000-000000000041', 'Tenant WO Sale', 'bengkel');

insert into public.outlets (id, tenant_id, name) values
  ('f3000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'Bengkel Uji');

insert into public.memberships (tenant_id, user_id, role) values
  ('f2000000-0000-0000-0000-000000000041', 'f1000000-0000-0000-0000-000000000041', 'owner'),
  ('f2000000-0000-0000-0000-000000000041', 'f1000000-0000-0000-0000-000000000042', 'kasir');

insert into public.units (id, tenant_id, name) values
  ('f5000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'pcs');

insert into public.categories (id, tenant_id, name) values
  ('f6100000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'Jasa dan Sparepart');

insert into public.products (id, tenant_id, name, sku, category_id, base_unit_id, kind, track_stock, sell_price, cost_price) values
  ('f7000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'Oli Uji', 'OLI-UJI', 'f6100000-0000-0000-0000-000000000041', 'f5000000-0000-0000-0000-000000000041', 'barang', true, 50000, 30000),
  ('f7000000-0000-0000-0000-000000000042', 'f2000000-0000-0000-0000-000000000041', 'Jasa Uji', 'JASA-UJI', 'f6100000-0000-0000-0000-000000000041', 'f5000000-0000-0000-0000-000000000041', 'jasa', false, 150000, 0);

insert into public.customers (id, tenant_id, name, active) values
  ('f6000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'Pelanggan WO', true);

insert into public.vehicles (id, tenant_id, customer_id, plate_no, active) values
  ('f9000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'f6000000-0000-0000-0000-000000000041', 'B 123 WO', true);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note) values
  ('f2000000-0000-0000-0000-000000000041', 'f7000000-0000-0000-0000-000000000041', 'f3000000-0000-0000-0000-000000000041', 5, 'adjustment', 'Stok awal');

insert into public.cash_shifts (id, tenant_id, outlet_id, cashier_id, opening_cash, client_uuid) values
  ('fc000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'f3000000-0000-0000-0000-000000000041', 'f1000000-0000-0000-0000-000000000041', 0, 'fd000000-0000-0000-0000-000000000041');

insert into public.work_orders (id, tenant_id, outlet_id, wo_no, queue_no, customer_id, vehicle_id, complaint, status, estimate_total) values
  ('fa000000-0000-0000-0000-000000000041', 'f2000000-0000-0000-0000-000000000041', 'f3000000-0000-0000-0000-000000000041', 'WO-TEST-0001', 1, 'f6000000-0000-0000-0000-000000000041', 'f9000000-0000-0000-0000-000000000041', 'Servis berkala', 'selesai', 250000),
  ('fa000000-0000-0000-0000-000000000042', 'f2000000-0000-0000-0000-000000000041', 'f3000000-0000-0000-0000-000000000041', 'WO-TEST-0002', 2, 'f6000000-0000-0000-0000-000000000041', 'f9000000-0000-0000-0000-000000000041', 'Belum selesai', 'dikerjakan', 0),
  ('fa000000-0000-0000-0000-000000000043', 'f2000000-0000-0000-0000-000000000041', 'f3000000-0000-0000-0000-000000000041', 'WO-TEST-0003', 3, 'f6000000-0000-0000-0000-000000000041', 'f9000000-0000-0000-0000-000000000041', 'Tanpa item', 'selesai', 0),
  ('fa000000-0000-0000-0000-000000000044', 'f2000000-0000-0000-0000-000000000041', 'f3000000-0000-0000-0000-000000000041', 'WO-TEST-0004', 4, 'f6000000-0000-0000-0000-000000000041', 'f9000000-0000-0000-0000-000000000041', 'Tagih tempo', 'selesai', 100000),
  ('fa000000-0000-0000-0000-000000000045', 'f2000000-0000-0000-0000-000000000041', 'f3000000-0000-0000-0000-000000000041', 'WO-TEST-0005', 5, 'f6000000-0000-0000-0000-000000000041', 'f9000000-0000-0000-0000-000000000041', 'Harga snapshot', 'selesai', 150000);

insert into public.work_order_items (tenant_id, work_order_id, product_id, unit_id, qty, qty_base, unit_price, line_total) values
  ('f2000000-0000-0000-0000-000000000041', 'fa000000-0000-0000-0000-000000000041', 'f7000000-0000-0000-0000-000000000041', 'f5000000-0000-0000-0000-000000000041', 2, 2, 50000, 100000),
  ('f2000000-0000-0000-0000-000000000041', 'fa000000-0000-0000-0000-000000000041', 'f7000000-0000-0000-0000-000000000042', 'f5000000-0000-0000-0000-000000000041', 1, 1, 150000, 150000),
  ('f2000000-0000-0000-0000-000000000041', 'fa000000-0000-0000-0000-000000000044', 'f7000000-0000-0000-0000-000000000041', 'f5000000-0000-0000-0000-000000000041', 2, 2, 50000, 100000),
  ('f2000000-0000-0000-0000-000000000041', 'fa000000-0000-0000-0000-000000000045', 'f7000000-0000-0000-0000-000000000042', 'f5000000-0000-0000-0000-000000000041', 1, 1, 150000, 150000);

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

select tests_set_user('f1000000-0000-0000-0000-000000000041');

select is(
  (public.create_work_order_sale(
    'fa000000-0000-0000-0000-000000000041',
    'fb000000-0000-0000-0000-000000000041',
    '[{"method":"tunai","amount":250000}]'::jsonb,
    'Penagihan servis',
    'fc000000-0000-0000-0000-000000000041'
  ) ->> 'status'),
  'paid',
  'OWNER: WO selesai dikonversi menjadi sale paid'
);

select tests_set_postgres();
select is(
  (select (status, sale_id is not null) from public.work_orders where id = 'fa000000-0000-0000-0000-000000000041'),
  ('ditagih'::text, true),
  'VERIF: WO ditautkan ke sale dan berstatus ditagih'
);

select is(
  (select (customer_id, vehicle_id, work_order_id, total) from public.sales where client_uuid = 'fb000000-0000-0000-0000-000000000041'),
  ('f6000000-0000-0000-0000-000000000041'::uuid, 'f9000000-0000-0000-0000-000000000041'::uuid, 'fa000000-0000-0000-0000-000000000041'::uuid, 250000::bigint),
  'VERIF: sale memakai customer, kendaraan, dan total dari item WO'
);

select is(
  (select count(*)::int from public.sale_items where sale_id = (select sale_id from public.work_orders where id = 'fa000000-0000-0000-0000-000000000041')),
  2,
  'VERIF: dua item WO menjadi dua sale item'
);

select is(
  (select qty_base from public.stock_levels where tenant_id = 'f2000000-0000-0000-0000-000000000041' and product_id = 'f7000000-0000-0000-0000-000000000041' and outlet_id = 'f3000000-0000-0000-0000-000000000041'),
  3::numeric,
  'VERIF: stok hanya dipotong oleh sale (5 - 2 = 3)'
);

select tests_set_user('f1000000-0000-0000-0000-000000000041');
select is(
  (public.create_work_order_sale(
    'fa000000-0000-0000-0000-000000000041',
    'fb000000-0000-0000-0000-000000000099',
    '[{"method":"tunai","amount":250000}]'::jsonb,
    null,
    'fc000000-0000-0000-0000-000000000041'
  ) ->> 'idempotent')::boolean,
  true,
  'IDEMPOTEN: WO yang sama mengembalikan sale yang telah ada'
);

select tests_set_postgres();
select is(
  (select count(*)::int from public.sales where work_order_id = 'fa000000-0000-0000-0000-000000000041'),
  1,
  'VERIF: tidak ada sale dobel untuk satu WO'
);

select is(
  (select count(*)::int from public.stock_movements where ref_type = 'sale' and ref_id = (select sale_id from public.work_orders where id = 'fa000000-0000-0000-0000-000000000041')),
  1,
  'VERIF: tidak ada stock movement dobel'
);

select tests_set_user('f1000000-0000-0000-0000-000000000042');
select throws_ok(
  $q$ select public.create_work_order_sale(
    'fa000000-0000-0000-0000-000000000042',
    'fb000000-0000-0000-0000-000000000042',
    '[{"method":"tunai","amount":1}]'::jsonb,
    null,
    'fc000000-0000-0000-0000-000000000041'
  ) $q$,
  'P0001',
  'Work order harus berstatus selesai sebelum ditagihkan',
  'KASIR: WO belum selesai tidak bisa ditagihkan'
);

select tests_set_postgres();
select is(
  (select sale_id is null from public.work_orders where id = 'fa000000-0000-0000-0000-000000000042'),
  true,
  'VERIF: WO belum selesai tidak memiliki sale'
);

select tests_set_user('f1000000-0000-0000-0000-000000000041');
select throws_ok(
  $q$ select public.create_work_order_sale(
    'fa000000-0000-0000-0000-000000000043',
    'fb000000-0000-0000-0000-000000000043',
    '[{"method":"tunai","amount":1}]'::jsonb,
    null,
    'fc000000-0000-0000-0000-000000000041'
  ) $q$,
  'P0001',
  'Work order belum memiliki item untuk ditagihkan',
  'OWNER: WO tanpa item tidak bisa ditagihkan'
);

select tests_set_postgres();
select is(
  (select sale_id is null from public.work_orders where id = 'fa000000-0000-0000-0000-000000000043'),
  true,
  'VERIF: WO tanpa item tidak memiliki sale'
);

select is(
  (select count(*)::int from public.audit_logs where entity = 'work_order' and action = 'convert_to_sale'),
  1,
  'AUDIT: konversi WO tercatat satu kali'
);

-- ═══ Kredit / tempo: nominal wajib sama dengan total work order ═══════════
select tests_set_user('f1000000-0000-0000-0000-000000000041');
select throws_ok(
  $q$ select public.create_work_order_sale(
    'fa000000-0000-0000-0000-000000000044',
    'fb000000-0000-0000-0000-000000000044',
    '[{"method":"kredit_tempo","amount":1}]'::jsonb,
    null,
    'fc000000-0000-0000-0000-000000000041'
  ) $q$,
  'P0001',
  'Nominal kredit/tempo harus sama dengan total work order (100000)',
  'KREDIT: nominal bebas ditolak'
);

select tests_set_postgres();
select is(
  (select sale_id is null from public.work_orders where id = 'fa000000-0000-0000-0000-000000000044'),
  true,
  'VERIF: kredit gagal tidak menautkan sale'
);

select tests_set_user('f1000000-0000-0000-0000-000000000041');
select is(
  (public.create_work_order_sale(
    'fa000000-0000-0000-0000-000000000044',
    'fb000000-0000-0000-0000-000000000044',
    '[{"method":"kredit_tempo","amount":100000}]'::jsonb,
    null,
    'fc000000-0000-0000-0000-000000000041'
  ) ->> 'status'),
  'credit',
  'KREDIT: tempo menghasilkan penjualan berstatus credit'
);

select tests_set_postgres();
select is(
  (select (s.total, s.paid_amount, r.amount)
   from public.sales s
   join public.receivables r on r.sale_id = s.id
   where s.client_uuid = 'fb000000-0000-0000-0000-000000000044'),
  (100000::bigint, 0::bigint, 100000::bigint),
  'VERIF: piutang tempo sama dengan total work order'
);

-- ═══ Harga snapshot WO dihormati walau harga jual sudah berubah ══════════
update public.products
set sell_price = 175000
where id = 'f7000000-0000-0000-0000-000000000042';

select tests_set_user('f1000000-0000-0000-0000-000000000041');
select is(
  (public.create_work_order_sale(
    'fa000000-0000-0000-0000-000000000045',
    'fb000000-0000-0000-0000-000000000045',
    '[{"method":"tunai","amount":150000}]'::jsonb,
    null,
    'fc000000-0000-0000-0000-000000000041'
  ) ->> 'total')::bigint,
  150000::bigint,
  'SNAPSHOT: harga di work order dipakai walau harga jual naik'
);

select tests_set_postgres();
select is(
  (select si.unit_price
   from public.sale_items si
   join public.sales s on s.id = si.sale_id
   where s.client_uuid = 'fb000000-0000-0000-0000-000000000045'),
  150000::bigint,
  'VERIF: sale item memakai harga snapshot, bukan harga jual baru'
);

-- ═══ Guard: sale_id dan status ditagih hanya lewat RPC konversi ══════════
select tests_set_user('f1000000-0000-0000-0000-000000000041');
select throws_ok(
  $q$ update public.work_orders
      set sale_id = 'fb000000-0000-0000-0000-000000000041'
      where id = 'fa000000-0000-0000-0000-000000000042' $q$,
  '42501',
  'sale_id work order hanya boleh diisi lewat konversi penjualan',
  'GUARD: owner tidak bisa mengisi sale_id langsung'
);

select throws_ok(
  $q$ update public.work_orders
      set status = 'ditagih'
      where id = 'fa000000-0000-0000-0000-000000000042' $q$,
  '42501',
  'Status ditagih hanya bisa didapat lewat konversi penjualan',
  'GUARD: status ditagih tidak bisa di-set langsung'
);

select throws_ok(
  $q$ select public.update_work_order_status(
    'fa000000-0000-0000-0000-000000000042', 'ditagih'
  ) $q$,
  'P0001',
  'Status ditagih hanya bisa didapat lewat konversi penjualan',
  'GUARD: RPC ubah status menolak ditagih'
);

select tests_set_postgres();
select is(
  (select (sale_id is null, status) from public.work_orders where id = 'fa000000-0000-0000-0000-000000000042'),
  (true, 'dikerjakan'::text),
  'VERIF: guard tidak mengubah sale_id maupun status WO'
);

select * from finish();
rollback;