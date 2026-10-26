-- Tes pgTAP 0017: pos_catalog (harga server, stok, satuan, tanpa HPP)
begin;
select plan(10);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'b8000000-0000-0000-0000-000000000001', 'authenticated', 'kasir.pos@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b8000000-0000-0000-0000-000000000002', 'authenticated', 'owner2.pos@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('b9000000-0000-0000-0000-000000000001', 'Tenant Pos A', 'toko_bangunan'),
  ('b9000000-0000-0000-0000-000000000002', 'Tenant Pos B', 'bengkel');

insert into public.memberships (tenant_id, user_id, role) values
  ('b9000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 'kasir'),
  ('b9000000-0000-0000-0000-000000000002', 'b8000000-0000-0000-0000-000000000002', 'owner');

insert into public.outlets (id, tenant_id, name)
values ('ba000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000001', 'Outlet Pos');

insert into public.units (id, tenant_id, name) values
  ('bb000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000001', 'pcs'),
  ('bb000000-0000-0000-0000-000000000002', 'b9000000-0000-0000-0000-000000000001', 'sak');

insert into public.products (id, tenant_id, name, sku, base_unit_id, kind, track_stock, sell_price, cost_price, min_stock)
values
  ('bc000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000001',
   'Semen Pos', 'SEMEN-POS', 'bb000000-0000-0000-0000-000000000001', 'barang', true, 10000, 7000, 5),
  ('bc000000-0000-0000-0000-000000000002', 'b9000000-0000-0000-0000-000000000001',
   'Jasa Pos', 'JASA-POS', 'bb000000-0000-0000-0000-000000000001', 'jasa', false, 50000, 0, 0);

insert into public.product_units (tenant_id, product_id, unit_id, factor_to_base, sell_price)
values ('b9000000-0000-0000-0000-000000000001',
        'bc000000-0000-0000-0000-000000000001',
        'bb000000-0000-0000-0000-000000000002', 40, 360000);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note)
values ('b9000000-0000-0000-0000-000000000001',
        'bc000000-0000-0000-0000-000000000001',
        'ba000000-0000-0000-0000-000000000001', 3, 'adjustment', 'Stok awal');

create or replace function tests_set_user(p_user uuid) returns void
  language plpgsql as $$
  begin
    execute format('set local "request.jwt.claims" to %L', json_build_object('sub', p_user, 'role', 'authenticated'));
    execute format('set local role %I', 'authenticated');
  end;
  $$;

select tests_set_user('b8000000-0000-0000-0000-000000000001');

-- (1) Kasir mendapat produk aktif
select is(
  (select count(*)::int from public.pos_catalog(
    'b9000000-0000-0000-0000-000000000001',
    'ba000000-0000-0000-0000-000000000001',
    null)),
  2, 'POS: 2 produk aktif terlihat'
);

-- (2) Harga base sesuai harga jual
select is(
  (select price from public.pos_catalog(
    'b9000000-0000-0000-0000-000000000001',
    'ba000000-0000-0000-0000-000000000001',
    null)
   where sku = 'SEMEN-POS'),
  10000::bigint, 'POS: harga base 10000'
);

-- (3) Harga satuan sak dari product_units
select is(
  (select (u ->> 'price')::bigint
   from public.pos_catalog(
     'b9000000-0000-0000-0000-000000000001',
     'ba000000-0000-0000-0000-000000000001',
     null) c,
   jsonb_array_elements(c.units) u
   where c.sku = 'SEMEN-POS' and u ->> 'name' = 'sak'),
  360000::bigint, 'POS: harga 1 sak 360000'
);

-- (4) Jumlah opsi satuan = base + sak
select is(
  (select jsonb_array_length(units)
   from public.pos_catalog(
     'b9000000-0000-0000-0000-000000000001',
     'ba000000-0000-0000-0000-000000000001',
     null)
   where sku = 'SEMEN-POS'),
  2, 'POS: 2 opsi satuan (pcs + sak)'
);

-- (5) Stok outlet terbaca
select is(
  (select stock_qty from public.pos_catalog(
    'b9000000-0000-0000-0000-000000000001',
    'ba000000-0000-0000-0000-000000000001',
    null)
   where sku = 'SEMEN-POS'),
  3::numeric, 'POS: stok 3'
);

-- (6) Stok menipis (3 < min 5)
select is(
  (select is_low from public.pos_catalog(
    'b9000000-0000-0000-0000-000000000001',
    'ba000000-0000-0000-0000-000000000001',
    null)
   where sku = 'SEMEN-POS'),
  true, 'POS: is_low true'
);

-- (7) Jasa tidak melacak stok
select is(
  (select track_stock from public.pos_catalog(
    'b9000000-0000-0000-0000-000000000001',
    'ba000000-0000-0000-0000-000000000001',
    null)
   where sku = 'JASA-POS'),
  false, 'POS: jasa track_stock false'
);

-- (8) Hasil fungsi tidak memuat kolom biaya
select is(
  (select count(*)::int
   from information_schema.columns
   where table_schema = 'public'
     and table_name = 'pos_catalog'
     and column_name in ('cost_price', 'unit_cost')),
  0, 'POS: tidak ada kolom biaya di pos_catalog'
);

-- (9) Owner tenant B tidak boleh memanggil
select tests_set_user('b8000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select * from public.pos_catalog(
        'b9000000-0000-0000-0000-000000000001',
        'ba000000-0000-0000-0000-000000000001', null) $q$,
  '42501',
  'Tidak berhak membaca katalog tenant ini',
  'POS: tenant lain ditolak'
);

-- (10) Outlet asing ditolak
select tests_set_user('b8000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select * from public.pos_catalog(
        'b9000000-0000-0000-0000-000000000001',
        'ba000000-0000-0000-0000-0000000000ff', null) $q$,
  'P0001',
  'Outlet tidak ditemukan',
  'POS: outlet asing ditolak'
);

select * from finish();
rollback;
