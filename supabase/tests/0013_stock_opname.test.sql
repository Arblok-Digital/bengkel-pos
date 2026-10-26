-- Tes pgTAP 0013: stok opname (create → hitung → posting)
begin;
select plan(23);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'ac000000-0000-0000-0000-000000000001', 'authenticated', 'owner.opname@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'ac000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.opname@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'ac000000-0000-0000-0000-000000000003', 'authenticated', 'owner2.opname@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('ac100000-0000-0000-0000-000000000001', 'Tenant Opname A', 'bengkel'),
  ('ac100000-0000-0000-0000-000000000002', 'Tenant Opname B', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('ac100000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'owner'),
  ('ac100000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000002', 'kasir'),
  ('ac100000-0000-0000-0000-000000000002', 'ac000000-0000-0000-0000-000000000003', 'owner');

insert into public.outlets (id, tenant_id, name) values
  ('ac200000-0000-0000-0000-000000000001', 'ac100000-0000-0000-0000-000000000001', 'Outlet A'),
  ('ac200000-0000-0000-0000-000000000002', 'ac100000-0000-0000-0000-000000000002', 'Outlet B');

insert into public.units (id, tenant_id, name) values
  ('ac300000-0000-0000-0000-000000000001', 'ac100000-0000-0000-0000-000000000001', 'pcs'),
  ('ac300000-0000-0000-0000-000000000002', 'ac100000-0000-0000-0000-000000000002', 'pcs');

insert into public.products (id, tenant_id, name, base_unit_id, kind, track_stock, sell_price)
values
  ('ac400000-0000-0000-0000-000000000001', 'ac100000-0000-0000-0000-000000000001',
   'Produk Satu', 'ac300000-0000-0000-0000-000000000001', 'barang', true, 10000),
  ('ac400000-0000-0000-0000-000000000002', 'ac100000-0000-0000-0000-000000000001',
   'Produk Dua', 'ac300000-0000-0000-0000-000000000001', 'barang', true, 20000),
  ('ac400000-0000-0000-0000-000000000003', 'ac100000-0000-0000-0000-000000000001',
   'Jasa', 'ac300000-0000-0000-0000-000000000001', 'jasa', false, 50000);

insert into public.stock_movements (tenant_id, product_id, outlet_id, qty_base, type, note)
values
  ('ac100000-0000-0000-0000-000000000001', 'ac400000-0000-0000-0000-000000000001',
   'ac200000-0000-0000-0000-000000000001', 10, 'adjustment', 'Stok awal'),
  ('ac100000-0000-0000-0000-000000000001', 'ac400000-0000-0000-0000-000000000002',
   'ac200000-0000-0000-0000-000000000001', 5, 'adjustment', 'Stok awal');

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

-- (1) kasir tidak boleh membuat opname
select tests_set_user('ac000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.create_stock_opname(
        'ac100000-0000-0000-0000-000000000001',
        'ac200000-0000-0000-0000-000000000001', 'Coba kasir') $q$,
  '42501',
  'Tidak berhak membuat opname stok',
  'KASIR: create opname ditolak'
);

-- (2) owner membuat opname
select tests_set_user('ac000000-0000-0000-0000-000000000001');
select is(
  (public.create_stock_opname(
    'ac100000-0000-0000-0000-000000000001',
    'ac200000-0000-0000-0000-000000000001', 'Opname bulanan')) is not null,
  true, 'OWNER: create opname'
);

-- (3) hanya produk track_stock yang masuk item
select is(
  count(*)::int, 2, 'OPNAME: 2 item (jasa tidak ikut)'
) from public.stock_opname_items
where tenant_id = 'ac100000-0000-0000-0000-000000000001';

-- (4) system_qty tersalin dari stok
select is(
  (select system_qty from public.stock_opname_items
    where tenant_id = 'ac100000-0000-0000-0000-000000000001'
      and product_id = 'ac400000-0000-0000-0000-000000000001'),
  10::numeric, 'OPNAME: system_qty produk satu = 10'
);

-- (5) kasir boleh melihat opname
select tests_set_user('ac000000-0000-0000-0000-000000000002');
select is(
  count(*)::int, 1, 'KASIR: melihat opname tenant-nya'
) from public.stock_opnames;

-- (6) tenant B tidak melihat opname tenant A
select tests_set_user('ac000000-0000-0000-0000-000000000003');
select is(
  count(*)::int, 0, 'OWNER B: tidak melihat opname tenant A'
) from public.stock_opnames;

-- (7) insert opname langsung ditolak
select tests_set_user('ac000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ insert into public.stock_opnames (tenant_id, outlet_id)
      values ('ac100000-0000-0000-0000-000000000001',
              'ac200000-0000-0000-0000-000000000001') $q$,
  '42501',
  'permission denied for table stock_opnames',
  'OWNER: insert opname langsung ditolak'
);

-- (8) kasir tidak boleh menyimpan hitungan
select tests_set_user('ac000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.save_stock_opname_counts(
        (select id from public.stock_opnames limit 1), '[]'::jsonb) $q$,
  '42501',
  'Tidak berhak menyimpan hitungan',
  'KASIR: save counts ditolak'
);

-- (9) owner menyimpan hitungan
select tests_set_user('ac000000-0000-0000-0000-000000000001');
select is(
  public.save_stock_opname_counts(
    (select id from public.stock_opnames where tenant_id = 'ac100000-0000-0000-0000-000000000001' order by created_at limit 1),
    (select jsonb_agg(jsonb_build_object(
        'item_id', i.id,
        'counted_qty', case when i.product_id = 'ac400000-0000-0000-0000-000000000001' then 8 else 5 end))
     from public.stock_opname_items i
     where i.tenant_id = 'ac100000-0000-0000-0000-000000000001'
       and i.opname_id = (select id from public.stock_opnames
                          where tenant_id = 'ac100000-0000-0000-0000-000000000001'
                          order by created_at limit 1))),
  2, 'OWNER: simpan 2 hitungan'
);

-- (10) verifikasi counted
select tests_set_postgres();
select is(
  (select counted_qty from public.stock_opname_items
    where product_id = 'ac400000-0000-0000-0000-000000000001'),
  8::numeric, 'VERIF: hitungan produk satu = 8'
);

-- (11) qty hitung negatif ditolak
select tests_set_user('ac000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.save_stock_opname_counts(
        (select id from public.stock_opnames
          where tenant_id = 'ac100000-0000-0000-0000-000000000001' order by created_at limit 1),
        (select jsonb_agg(jsonb_build_object('item_id', i.id, 'counted_qty', -1))
         from public.stock_opname_items i
         where i.product_id = 'ac400000-0000-0000-0000-000000000001')) $q$,
  'P0001',
  'Qty hitung tidak boleh negatif',
  'OPNAME: hitungan negatif ditolak'
);

-- (12) verifikasi hitungan tidak berubah
select tests_set_postgres();
select is(
  (select counted_qty from public.stock_opname_items
    where product_id = 'ac400000-0000-0000-0000-000000000001'),
  8::numeric, 'VERIF: hitungan tetap 8'
);

-- (13) kasir tidak boleh posting
select tests_set_user('ac000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.post_stock_opname(
        (select id from public.stock_opnames limit 1)) $q$,
  '42501',
  'Tidak berhak memposting opname',
  'KASIR: posting ditolak'
);

-- (14) owner posting
select tests_set_user('ac000000-0000-0000-0000-000000000001');
select is(
  public.post_stock_opname(
    (select id from public.stock_opnames
      where tenant_id = 'ac100000-0000-0000-0000-000000000001' order by created_at limit 1)),
  1, 'OWNER: posting menghasilkan 1 movement'
);

-- (15) status posted
select tests_set_postgres();
select is(
  (select status from public.stock_opnames
    where tenant_id = 'ac100000-0000-0000-0000-000000000001' order by created_at limit 1),
  'posted', 'VERIF: status opname posted'
);

-- (16) stok produk satu menjadi 8
select is(
  (select qty_base from public.stock_levels
    where tenant_id = 'ac100000-0000-0000-0000-000000000001'
      and product_id = 'ac400000-0000-0000-0000-000000000001'),
  8::numeric, 'STOK: produk satu menjadi 8'
);

-- (17) movement opname tercatat
select is(
  count(*)::int, 1, 'MOVEMENT: 1 opname movement'
) from public.stock_movements
where tenant_id = 'ac100000-0000-0000-0000-000000000001'
  and type = 'opname';

-- (18) system_qty & difference diperbarui
select is(
  (select difference from public.stock_opname_items
    where product_id = 'ac400000-0000-0000-0000-000000000001'),
  (-2)::numeric, 'OPNAME: difference -2'
);

-- (19) posting ulang ditolak
select tests_set_user('ac000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.post_stock_opname(
        (select id from public.stock_opnames
          where tenant_id = 'ac100000-0000-0000-0000-000000000001' order by created_at limit 1)) $q$,
  'P0001',
  'Hanya opname draft yang bisa diposting',
  'OPNAME: posting ulang ditolak'
);

-- (20) simpan hitungan setelah posted ditolak
select throws_ok(
  $q$ select public.save_stock_opname_counts(
        (select id from public.stock_opnames
          where tenant_id = 'ac100000-0000-0000-0000-000000000001' order by created_at limit 1),
        '[]'::jsonb) $q$,
  'P0001',
  'Hanya opname draft yang bisa diubah',
  'OPNAME: ubah setelah posted ditolak'
);

-- (21) posting tanpa hitungan ditolak
select is(
  (public.create_stock_opname(
    'ac100000-0000-0000-0000-000000000001',
    'ac200000-0000-0000-0000-000000000001', 'Kosong')) is not null,
  true, 'OWNER: buat opname kosong'
);
select throws_ok(
  $q$ select public.post_stock_opname(
        (select id from public.stock_opnames
          where tenant_id = 'ac100000-0000-0000-0000-000000000001'
            and note = 'Kosong')) $q$,
  'P0001',
  'Belum ada item yang dihitung',
  'OPNAME: posting tanpa hitungan ditolak'
);

-- (22) owner tenant B tidak boleh posting opname tenant A
select tests_set_postgres();
insert into public.stock_opnames (id, tenant_id, outlet_id, note)
values ('ac600000-0000-0000-0000-000000000001',
        'ac100000-0000-0000-0000-000000000001',
        'ac200000-0000-0000-0000-000000000001', 'Cross tenant');

select tests_set_user('ac000000-0000-0000-0000-000000000003');
select throws_ok(
  $q$ select public.post_stock_opname('ac600000-0000-0000-0000-000000000001') $q$,
  '42501',
  'Tidak berhak memposting opname',
  'OWNER B: posting opname tenant A ditolak'
);

select * from finish();
rollback;
