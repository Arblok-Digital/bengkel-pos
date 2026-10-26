-- 0004: role dev dengan akses penuh ke semua tenant
-- Referensi: AGENTS.md Bagian 3 (skema & keamanan), ARCHITECTURE.md Bagian 2.
--
-- Role dev = user yang diberi role 'dev' (aktif) di minimal satu tenant.
-- Setelah itu dev dapat:
--   * SELECT semua tenant / outlet / membership (tidak terbatas tenant miliknya)
--   * INSERT/UPDATE/DELETE outlet dan membership di semua tenant
-- Role dev TIDAK boleh:
--   * Membuat/hard-delete tenant lewat API (masih lewat RPC onboarding T1.2)
--   * Melewati trigger prevent_tenant_change (tenant_id immutable)
--   * Melewati trigger protect_last_owner (minimal 1 owner aktif per tenant)

-- ─── 1. Tambahkan 'dev' ke daftar role yang diizinkan ────────────────────────
alter table public.memberships
  drop constraint memberships_role_check;

alter table public.memberships
  add constraint memberships_role_check
  check (role in ('owner', 'admin', 'kasir', 'mekanik', 'gudang', 'dev'));

-- ─── 2. Helper: apakah user saat ini ber-role dev (aktif) di tenant mana pun ─
create function public.is_dev() returns boolean
  language sql stable security definer
  set search_path = public
  as $$
    select exists (
      select 1
      from public.memberships m
      where m.user_id = auth.uid()
        and m.active
        and m.role = 'dev'
    );
  $$;

revoke execute on function public.is_dev() from public, anon;
grant execute on function public.is_dev() to authenticated;

-- ─── 3. tenants: SELECT anggota atau dev ─────────────────────────────────────
drop policy if exists tenants_select_member on public.tenants;
create policy tenants_select_member_or_dev on public.tenants
  for select to authenticated
  using (public.is_member(id) or public.is_dev());

-- UPDATE tenant: owner/admin atau dev
drop policy if exists tenants_update_admin on public.tenants;
create policy tenants_update_admin_or_dev on public.tenants
  for update to authenticated
  using (public.has_role(id, array['owner','admin']) or public.is_dev())
  with check (public.has_role(id, array['owner','admin']) or public.is_dev());

-- (INSERT/DELETE tenant tanpa policy: ditolak untuk semua role API;
-- pembuatan tenant hanya lewat RPC onboarding, hard-delete dilarang.)

-- ─── 4. outlets: anggota atau dev dapat mengelola di semua tenant ─────────────
drop policy if exists outlets_select_member on public.outlets;
create policy outlets_select_member_or_dev on public.outlets
  for select to authenticated
  using (public.is_member(tenant_id) or public.is_dev());

drop policy if exists outlets_insert_admin on public.outlets;
create policy outlets_insert_admin_or_dev on public.outlets
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner','admin']) or public.is_dev());

drop policy if exists outlets_update_admin on public.outlets;
create policy outlets_update_admin_or_dev on public.outlets
  for update to authenticated
  using (public.has_role(tenant_id, array['owner','admin']) or public.is_dev())
  with check (public.has_role(tenant_id, array['owner','admin']) or public.is_dev());

drop policy if exists outlets_delete_admin on public.outlets;
create policy outlets_delete_admin_or_dev on public.outlets
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner','admin']) or public.is_dev());

-- ─── 5. memberships: anggota dapat melihat, admin/dev dapat mengelola ─────────
drop policy if exists memberships_select_member on public.memberships;
create policy memberships_select_member_or_dev on public.memberships
  for select to authenticated
  using (public.is_member(tenant_id) or public.is_dev());

drop policy if exists memberships_insert_admin on public.memberships;
create policy memberships_insert_admin_or_dev on public.memberships
  for insert to authenticated
  with check (
    (public.has_role(tenant_id, array['owner','admin']) or public.is_dev())
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']) or public.is_dev())
    and auth.uid() is distinct from user_id
  );

drop policy if exists memberships_update_admin on public.memberships;
create policy memberships_update_admin_or_dev on public.memberships
  for update to authenticated
  using (
    (public.has_role(tenant_id, array['owner','admin']) or public.is_dev())
    and auth.uid() is distinct from user_id
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']) or public.is_dev())
  )
  with check (
    (public.has_role(tenant_id, array['owner','admin']) or public.is_dev())
    and auth.uid() is distinct from user_id
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']) or public.is_dev())
  );

drop policy if exists memberships_delete_admin on public.memberships;
create policy memberships_delete_admin_or_dev on public.memberships
  for delete to authenticated
  using (
    (public.has_role(tenant_id, array['owner','admin']) or public.is_dev())
    and auth.uid() is distinct from user_id
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']) or public.is_dev())
  );

-- ─── 6. Indeks (dev juga filtering per tenant, jadi indeks (tenant_id, …) ──
--       sudah cukup; tidak ada indeks baru yang diperlukan di migrasi ini.
