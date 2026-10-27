-- seed.sql bengkel-pos
-- Data demo untuk pengembangan lokal (dipakai juga oleh e2e).
-- Akun: admin@bengkel.test / bengkel123 (owner Bengkel Maju Jaya).
-- Jangan dipakai di produksi.

do $$
declare
  v_user uuid := 'f0000000-0000-0000-0000-000000000001';
  v_tenant uuid := 'f1111111-1111-1111-1111-111111111111';
  v_outlet uuid := 'f2222222-2222-2222-2222-222222222222';
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated',
    'admin@bengkel.test', extensions.crypt('bengkel123', extensions.gen_salt('bf')), now(),
    '', '', '', '', '', '', '', '',
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  )
  on conflict (id) do nothing;

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_user,
    jsonb_build_object('sub', v_user::text, 'email', 'admin@bengkel.test'),
    'email', 'admin@bengkel.test', now(), now(), now()
  )
  on conflict do nothing;

  insert into public.tenants (id, name, business_type, client_uuid, created_by)
  values (v_tenant, 'Bengkel Maju Jaya', 'both', gen_random_uuid(), v_user)
  on conflict (id) do nothing;

  insert into public.outlets (id, tenant_id, name, created_by)
  values (v_outlet, v_tenant, 'Outlet Utama', v_user)
  on conflict (id) do nothing;

  insert into public.units (id, tenant_id, name, created_by) values
    ('f3000000-0000-0000-0000-000000000001', v_tenant, 'pcs', v_user),
    ('f3000000-0000-0000-0000-000000000002', v_tenant, 'kg', v_user),
    ('f3000000-0000-0000-0000-000000000003', v_tenant, 'liter', v_user),
    ('f3000000-0000-0000-0000-000000000004', v_tenant, 'sak', v_user),
    ('f3000000-0000-0000-0000-000000000005', v_tenant, 'meter', v_user),
    ('f3000000-0000-0000-0000-000000000006', v_tenant, 'set', v_user),
    ('f3000000-0000-0000-0000-000000000007', v_tenant, 'dus', v_user),
    ('f3000000-0000-0000-0000-000000000008', v_tenant, 'batang', v_user)
  on conflict (tenant_id, name) do nothing;

  insert into public.memberships (tenant_id, user_id, role, created_by)
  values (v_tenant, v_user, 'owner', v_user)
  on conflict (tenant_id, user_id) do nothing;

  -- Produk demo + stok awal (movement, bukan update stock_levels)
  insert into public.products (id, tenant_id, name, sku, barcode, base_unit_id, kind, sell_price, min_stock, created_by)
  values
    ('f6000000-0000-0000-0000-000000000001', v_tenant, 'Oli Mesin 1L', 'OLI-1L', '8999001',
     'f3000000-0000-0000-0000-000000000003', 'barang', 55000, 2, v_user),
    ('f6000000-0000-0000-0000-000000000002', v_tenant, 'Semen 40kg', 'SEMEN-1', '8999002',
     'f3000000-0000-0000-0000-000000000004', 'barang', 65000, 5, v_user)
  on conflict (id) do nothing;

  insert into public.stock_movements (id, tenant_id, product_id, outlet_id, qty_base, type, note, created_by)
  values
    ('f7000000-0000-0000-0000-000000000001', v_tenant,
     'f6000000-0000-0000-0000-000000000001', v_outlet, 10, 'adjustment', 'Stok awal demo', v_user),
    ('f7000000-0000-0000-0000-000000000002', v_tenant,
     'f6000000-0000-0000-0000-000000000001', v_outlet, -3, 'sale', 'Penjualan demo', v_user),
    ('f7000000-0000-0000-0000-000000000003', v_tenant,
     'f6000000-0000-0000-0000-000000000002', v_outlet, 500, 'adjustment', 'Stok awal demo', v_user),
    ('f7000000-0000-0000-0000-000000000004', v_tenant,
     'f6000000-0000-0000-0000-000000000002', v_outlet, -18, 'sale', 'Penjualan demo', v_user)
  on conflict (id) do nothing;
end $$;
