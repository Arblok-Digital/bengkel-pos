-- 0002: RLS per perintah (kebuntuan celah "for all") + proteksi owner terakhir
-- Mengganti policy tunggal tenant_isolation dari 0001:
--   baca        = anggota tenant (is_member)
--   tulis       = hanya owner/admin (has_role), per perintah INSERT/UPDATE/DELETE
--   tenants     = INSERT/DELETE tanpa policy (ditolak; pembuatan lewat RPC di T1.2)
--   memberships = aturan khusus owner + larangan ubah diri sendiri
--                   + trigger proteksi owner aktif terakhir

drop policy if exists tenant_isolation on public.tenants;
drop policy if exists tenant_isolation on public.outlets;
drop policy if exists tenant_isolation on public.memberships;

-- ─── tenants ─────────────────────────────────────────────────────────────────
-- SELECT: setiap member
create policy tenants_select_member on public.tenants
  for select to authenticated
  using (public.is_member(id));

-- UPDATE: hanya owner/admin
create policy tenants_update_admin on public.tenants
  for update to authenticated
  using (public.has_role(id, array['owner', 'admin']))
  with check (public.has_role(id, array['owner', 'admin']));

-- INSERT tanpa policy: ditolak untuk semua role API (pembuatan tenant lewat RPC di T1.2).
-- DELETE tanpa policy: tenant tidak boleh di-hard-delete lewat API.

-- ─── outlets ─────────────────────────────────────────────────────────────────
create policy outlets_select_member on public.outlets
  for select to authenticated
  using (public.is_member(tenant_id));

create policy outlets_insert_admin on public.outlets
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));

create policy outlets_update_admin on public.outlets
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));

create policy outlets_delete_admin on public.outlets
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

-- ─── memberships ─────────────────────────────────────────────────────────────
create policy memberships_select_member on public.memberships
  for select to authenticated
  using (public.is_member(tenant_id));

-- INSERT: owner/admin; hanya owner yang boleh membuat row ber-role owner;
-- tidak ada yang boleh membuat membership untuk dirinya sendiri lewat API.
create policy memberships_insert_admin on public.memberships
  for insert to authenticated
  with check (
    public.has_role(tenant_id, array['owner', 'admin'])
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']))
    and auth.uid() is distinct from user_id
  );

-- UPDATE: owner/admin, bukan baris diri sendiri, dan hanya owner yang
-- boleh menyentuh baris ber-role owner.
create policy memberships_update_admin on public.memberships
  for update to authenticated
  using (
    public.has_role(tenant_id, array['owner', 'admin'])
    and auth.uid() is distinct from user_id
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']))
  )
  with check (
    public.has_role(tenant_id, array['owner', 'admin'])
    and auth.uid() is distinct from user_id
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']))
  );

-- DELETE: owner/admin, bukan baris diri sendiri, dan hanya owner yang
-- boleh menghapus baris ber-role owner.
create policy memberships_delete_admin on public.memberships
  for delete to authenticated
  using (
    public.has_role(tenant_id, array['owner', 'admin'])
    and auth.uid() is distinct from user_id
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']))
  );

-- ─── trigger proteksi owner aktif terakhir ───────────────────────────────────
-- Sebelum UPDATE yang menurunkan role/menonaktifkan owner aktif, dan sebelum
-- DELETE owner aktif: jika tidak ada owner aktif lain, tolak (berlaku untuk
-- siapa pun, termasuk postgres, karena trigger dijalankan di bawah semua policy).
create function public.protect_last_owner() returns trigger
  language plpgsql
  set search_path = public
  as $$
  declare
    v_tenant uuid;
    v_other_owner int;
  begin
    if tg_op = 'DELETE' then
      if not (old.role = 'owner' and old.active) then
        return old;
      end if;
      v_tenant := old.tenant_id;
    else
      if not (old.role = 'owner' and old.active
              and (new.role <> 'owner' or new.active = false)) then
        return new;
      end if;
      v_tenant := old.tenant_id;
    end if;

    select count(*) into v_other_owner
    from public.memberships m
    where m.tenant_id = v_tenant
      and m.user_id is distinct from old.user_id
      and m.role = 'owner'
      and m.active;

    if v_other_owner = 0 then
      raise exception 'Owner aktif terakhir tidak boleh dihapus, diturunkan, atau dinonaktifkan (tenant %: hanya % owner aktif tersisa)',
        v_tenant, v_other_owner
        using errcode = 'P0001';
    end if;

    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end;
  $$;

create trigger memberships_protect_last_owner
  before update or delete on public.memberships
  for each row execute function public.protect_last_owner();

-- ─── set_created_by: client tidak boleh memalsukan created_by ────────────────
-- (mengganti versi di 0001; versi lama memprioritaskan nilai kiriman client)
create or replace function public.set_created_by() returns trigger
  language plpgsql
  set search_path = public
  as $$
  begin
    if tg_op = 'INSERT' then
      if auth.uid() is not null then
        new.created_by = auth.uid();
      end if;
    end if;
    return new;
  end;
  $$;
