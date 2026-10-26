-- Tes pgTAP 0014: shift kasir (buka → tutup, selisih, idempoten, RLS)
begin;
select plan(28);

create extension if not exists pgtap with schema extensions;

insert into auth.users (instance_id, id, aud, email, encrypted_password, email_confirmed_at, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'ad000000-0000-0000-0000-000000000001', 'authenticated', 'owner.shift@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'ad000000-0000-0000-0000-000000000002', 'authenticated', 'kasir.shift@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'ad000000-0000-0000-0000-000000000003', 'authenticated', 'kasir2.shift@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'ad000000-0000-0000-0000-000000000004', 'authenticated', 'owner2.shift@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'ad000000-0000-0000-0000-000000000005', 'authenticated', 'gudang.shift@uji.test', 'x', now(), '{"provider":"email","providers":["email"]}', now(), now());

insert into public.tenants (id, name, business_type) values
  ('ad100000-0000-0000-0000-000000000001', 'Tenant Shift A', 'bengkel'),
  ('ad100000-0000-0000-0000-000000000002', 'Tenant Shift B', 'toko_bangunan');

insert into public.memberships (tenant_id, user_id, role) values
  ('ad100000-0000-0000-0000-000000000001', 'ad000000-0000-0000-0000-000000000001', 'owner'),
  ('ad100000-0000-0000-0000-000000000001', 'ad000000-0000-0000-0000-000000000002', 'kasir'),
  ('ad100000-0000-0000-0000-000000000001', 'ad000000-0000-0000-0000-000000000003', 'kasir'),
  ('ad100000-0000-0000-0000-000000000001', 'ad000000-0000-0000-0000-000000000005', 'gudang'),
  ('ad100000-0000-0000-0000-000000000002', 'ad000000-0000-0000-0000-000000000004', 'owner');

insert into public.outlets (id, tenant_id, name) values
  ('ad200000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-000000000001', 'Outlet A'),
  ('ad200000-0000-0000-0000-000000000002', 'ad100000-0000-0000-0000-000000000002', 'Outlet B');

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

-- (1) gudang tidak boleh membuka shift
select tests_set_user('ad000000-0000-0000-0000-000000000005');
select throws_ok(
  $q$ select public.open_cash_shift(
        'ad100000-0000-0000-0000-000000000001',
        'ad200000-0000-0000-0000-000000000001',
        300000, 'ad900000-0000-0000-0000-0000000000ff') $q$,
  '42501',
  'Tidak berhak membuka shift kasir',
  'GUDANG: buka shift ditolak'
);

-- (2) kasir membuka shift
select tests_set_user('ad000000-0000-0000-0000-000000000002');
select is(
  (public.open_cash_shift(
    'ad100000-0000-0000-0000-000000000001',
    'ad200000-0000-0000-0000-000000000001',
    300000, 'ad900000-0000-0000-0000-000000000001')) is not null,
  true, 'KASIR: buka shift'
);

-- (3) verifikasi isi shift
select tests_set_postgres();
select is(
  (select (opening_cash, cashier_id, closed_at)
     from public.cash_shifts
     where client_uuid = 'ad900000-0000-0000-0000-000000000001'),
  (300000::bigint, 'ad000000-0000-0000-0000-000000000002'::uuid, null::timestamptz),
  'VERIF: modal awal 300000, kasir benar, belum ditutup'
);

-- (4) idempoten: client_uuid sama mengembalikan shift yang sama
select tests_set_user('ad000000-0000-0000-0000-000000000002');
select is(
  public.open_cash_shift(
    'ad100000-0000-0000-0000-000000000001',
    'ad200000-0000-0000-0000-000000000001',
    300000, 'ad900000-0000-0000-0000-000000000001'),
  (select id from public.cash_shifts
    where client_uuid = 'ad900000-0000-0000-0000-000000000001'),
  'KASIR: buka ulang dengan client_uuid sama = idempoten'
);

-- (5) verifikasi tidak ada shift dobel
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: hanya 1 shift tercatat'
) from public.cash_shifts
where tenant_id = 'ad100000-0000-0000-0000-000000000001';

-- (6) shift kedua tanpa menutup yang pertama ditolak
select tests_set_user('ad000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.open_cash_shift(
        'ad100000-0000-0000-0000-000000000001',
        'ad200000-0000-0000-0000-000000000001',
        100000, 'ad900000-0000-0000-0000-0000000000ff') $q$,
  'P0001',
  'Masih ada shift terbuka. Tutup dulu shift sebelumnya.',
  'KASIR: shift terbuka kedua ditolak'
);

-- (7) verifikasi tetap 1 shift
select tests_set_postgres();
select is(
  count(*)::int, 1, 'VERIF: tetap 1 shift'
) from public.cash_shifts
where tenant_id = 'ad100000-0000-0000-0000-000000000001'
  and cashier_id = 'ad000000-0000-0000-0000-000000000002';

-- (8) modal awal negatif ditolak
select tests_set_user('ad000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ select public.open_cash_shift(
        'ad100000-0000-0000-0000-000000000001',
        'ad200000-0000-0000-0000-000000000001',
        -1, 'ad900000-0000-0000-0000-0000000000fe') $q$,
  'P0001',
  'Modal awal tidak boleh negatif',
  'KASIR: modal awal negatif ditolak'
);

-- (9) kasir tenant B tidak boleh membuka shift tenant A
select tests_set_user('ad000000-0000-0000-0000-000000000004');
select throws_ok(
  $q$ select public.open_cash_shift(
        'ad100000-0000-0000-0000-000000000001',
        'ad200000-0000-0000-0000-000000000001',
        100000, 'ad900000-0000-0000-0000-0000000000fd') $q$,
  '42501',
  'Tidak berhak membuka shift kasir',
  'OWNER B: buka shift tenant A ditolak'
);

-- (10) insert langsung ditolak
select tests_set_user('ad000000-0000-0000-0000-000000000002');
select throws_ok(
  $q$ insert into public.cash_shifts
        (tenant_id, outlet_id, cashier_id, opening_cash, client_uuid)
      values ('ad100000-0000-0000-0000-000000000001',
              'ad200000-0000-0000-0000-000000000001',
              'ad000000-0000-0000-0000-000000000002',
              50000, 'ad900000-0000-0000-0000-0000000000fc') $q$,
  '42501',
  'permission denied for table cash_shifts',
  'KASIR: insert shift langsung ditolak'
);

-- (11) update langsung ditolak
select throws_ok(
  $q$ update public.cash_shifts set opening_cash = 999
      where client_uuid = 'ad900000-0000-0000-0000-000000000001' $q$,
  '42501',
  'permission denied for table cash_shifts',
  'KASIR: update shift langsung ditolak'
);

-- (12) verifikasi modal awal tidak berubah
select tests_set_postgres();
select is(
  (select opening_cash from public.cash_shifts
    where client_uuid = 'ad900000-0000-0000-0000-000000000001'),
  300000::bigint, 'VERIF: modal awal tetap 300000'
);

-- (13) kasir lain boleh membuka shift sendiri (paralel)
select tests_set_user('ad000000-0000-0000-0000-000000000003');
select is(
  (public.open_cash_shift(
    'ad100000-0000-0000-0000-000000000001',
    'ad200000-0000-0000-0000-000000000001',
    300000, 'ad900000-0000-0000-0000-000000000002')) is not null,
  true, 'KASIR 2: buka shift paralel di outlet sama'
);

-- (14) kasir melihat shift tenant-nya
select is(
  count(*)::int, 2, 'KASIR: melihat 2 shift tenant-nya'
) from public.cash_shifts
where tenant_id = 'ad100000-0000-0000-0000-000000000001';

-- (15) owner tenant B tidak melihat shift tenant A
select tests_set_user('ad000000-0000-0000-0000-000000000004');
select is(
  count(*)::int, 0, 'OWNER B: tidak melihat shift tenant A'
) from public.cash_shifts;

-- (16) kasir lain tidak boleh menutup shift bukan miliknya
select tests_set_user('ad000000-0000-0000-0000-000000000003');
select throws_ok(
  $q$ select public.close_cash_shift(
        (select id from public.cash_shifts
          where client_uuid = 'ad900000-0000-0000-0000-000000000001'),
        300000, null, 'adc00000-0000-0000-0000-0000000000f1') $q$,
  '42501',
  'Tidak berhak menutup shift ini',
  'KASIR 2: tutup shift kasir 1 ditolak'
);

-- (17) owner menutup shift kasir (selisih 0)
select tests_set_user('ad000000-0000-0000-0000-000000000001');
select is(
  (public.close_cash_shift(
    (select id from public.cash_shifts
      where client_uuid = 'ad900000-0000-0000-0000-000000000001'),
    300000, 'Tutup shift pagi', 'adc00000-0000-0000-0000-000000000001')
  ->> 'difference')::bigint,
  0::bigint, 'OWNER: tutup shift kasir, selisih 0'
);

-- (18) verifikasi expected & status tutup
select tests_set_postgres();
select is(
  (select (closing_cash_counted, expected_cash, difference, note,
           closed_at is not null)
     from public.cash_shifts
     where client_uuid = 'ad900000-0000-0000-0000-000000000001'),
  (300000::bigint, 300000::bigint, 0::bigint, 'Tutup shift pagi'::text, true),
  'VERIF: hitung 300000, expected 300000, selisih 0, catatan tersimpan'
);

-- (19) tutup ulang dengan client_uuid berbeda ditolak
select tests_set_user('ad000000-0000-0000-0000-000000000001');
select throws_ok(
  $q$ select public.close_cash_shift(
        (select id from public.cash_shifts
          where client_uuid = 'ad900000-0000-0000-0000-000000000001'),
        350000, null, 'adc00000-0000-0000-0000-0000000000f2') $q$,
  'P0001',
  'Shift sudah ditutup',
  'OWNER: tutup ulang shift ditolak'
);

-- (20) tutup ulang dengan client_uuid sama = idempoten
select is(
  (public.close_cash_shift(
    (select id from public.cash_shifts
      where client_uuid = 'ad900000-0000-0000-0000-000000000001'),
    300000, null, 'adc00000-0000-0000-0000-000000000001')
  ->> 'difference')::bigint,
  0::bigint, 'OWNER: tutup ulang client_uuid sama = idempoten'
);

-- (21) verifikasi nilai tutup tidak berubah
select tests_set_postgres();
select is(
  (select closing_cash_counted from public.cash_shifts
    where client_uuid = 'ad900000-0000-0000-0000-000000000001'),
  300000::bigint, 'VERIF: uang hitung tetap 300000'
);

-- (22) uang hitung negatif ditolak
select tests_set_user('ad000000-0000-0000-0000-000000000003');
select throws_ok(
  $q$ select public.close_cash_shift(
        (select id from public.cash_shifts
          where client_uuid = 'ad900000-0000-0000-0000-000000000002'),
        -5000, null, 'adc00000-0000-0000-0000-0000000000f3') $q$,
  'P0001',
  'Uang tunai dihitung tidak boleh negatif',
  'KASIR 2: uang hitung negatif ditolak'
);

-- (23) verifikasi shift kasir 2 masih terbuka
select tests_set_postgres();
select is(
  (select closed_at from public.cash_shifts
    where client_uuid = 'ad900000-0000-0000-0000-000000000002'),
  null::timestamptz, 'VERIF: shift kasir 2 masih terbuka'
);

-- (24) kasir menutup shift sendiri, selisih negatif dihitung apa adanya
select tests_set_user('ad000000-0000-0000-0000-000000000003');
select is(
  (public.close_cash_shift(
    (select id from public.cash_shifts
      where client_uuid = 'ad900000-0000-0000-0000-000000000002'),
    250000, null, 'adc00000-0000-0000-0000-000000000002')
  ->> 'difference')::bigint,
  (-50000)::bigint, 'KASIR 2: tutup shift, selisih -50000'
);

-- (25) setelah ditutup, kasir boleh membuka shift baru
select tests_set_user('ad000000-0000-0000-0000-000000000002');
select is(
  (public.open_cash_shift(
    'ad100000-0000-0000-0000-000000000001',
    'ad200000-0000-0000-0000-000000000001',
    150000, 'ad900000-0000-0000-0000-000000000003')) is not null,
  true, 'KASIR: buka shift baru setelah tutup'
);

-- (26) owner tenant B tidak boleh menutup shift tenant A
select tests_set_postgres();
create temp table shift_a3_id (id uuid);
insert into shift_a3_id
  select id from public.cash_shifts
  where client_uuid = 'ad900000-0000-0000-0000-000000000003';
grant select on shift_a3_id to authenticated;

select tests_set_user('ad000000-0000-0000-0000-000000000004');
select throws_ok(
  $q$ select public.close_cash_shift(
        (select id from shift_a3_id),
        150000, null, 'adc00000-0000-0000-0000-0000000000f4') $q$,
  '42501',
  'Tidak berhak menutup shift ini',
  'OWNER B: tutup shift tenant A ditolak'
);

-- (27) tenant_id tidak bisa diubah walau lewat owner (trigger)
select tests_set_postgres();
select throws_ok(
  $q$ update public.cash_shifts set tenant_id = 'ad100000-0000-0000-0000-000000000002'
      where client_uuid = 'ad900000-0000-0000-0000-000000000003' $q$,
  'P0001',
  'tenant_id tidak boleh diubah (tabel cash_shifts)',
  'DB: update tenant_id shift ditolak trigger'
);

-- (28) verifikasi tenant_id tidak berubah
select is(
  (select tenant_id from public.cash_shifts
    where client_uuid = 'ad900000-0000-0000-0000-000000000003'),
  'ad100000-0000-0000-0000-000000000001'::uuid,
  'VERIF: tenant_id shift tetap tenant A'
);

select * from finish();
rollback;
