-- 0005: hardening role dev — hanya dev yang boleh memberi/mengubah/menghapus
--        role dev.
-- Latar belakang: policy di 0004 mengizinkan owner/admin tenant mana pun
-- memberi role 'dev' ke user lain (atau menaikkan kasir menjadi dev). Karena
-- is_dev() berlaku global, itu berarti eskalasi dari admin satu tenant menjadi
-- admin semua tenant. Dev pertama dibuat lewat SQL/service role (operator).
--
-- Perubahan: syarat "role baru/lama bukan dev, ATAU pelaku adalah dev" pada
-- INSERT, UPDATE (using + with check), dan DELETE membership.

drop policy if exists memberships_insert_admin_or_dev on public.memberships;
create policy memberships_insert_admin_or_dev on public.memberships
  for insert to authenticated
  with check (
    (public.has_role(tenant_id, array['owner', 'admin']) or public.is_dev())
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']) or public.is_dev())
    and (role <> 'dev' or public.is_dev())
    and auth.uid() is distinct from user_id
  );

drop policy if exists memberships_update_admin_or_dev on public.memberships;
create policy memberships_update_admin_or_dev on public.memberships
  for update to authenticated
  using (
    (public.has_role(tenant_id, array['owner', 'admin']) or public.is_dev())
    and auth.uid() is distinct from user_id
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']) or public.is_dev())
    and (role <> 'dev' or public.is_dev())
  )
  with check (
    (public.has_role(tenant_id, array['owner', 'admin']) or public.is_dev())
    and auth.uid() is distinct from user_id
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']) or public.is_dev())
    and (role <> 'dev' or public.is_dev())
  );

drop policy if exists memberships_delete_admin_or_dev on public.memberships;
create policy memberships_delete_admin_or_dev on public.memberships
  for delete to authenticated
  using (
    (public.has_role(tenant_id, array['owner', 'admin']) or public.is_dev())
    and auth.uid() is distinct from user_id
    and (role <> 'owner' or public.has_role(tenant_id, array['owner']) or public.is_dev())
    and (role <> 'dev' or public.is_dev())
  );
