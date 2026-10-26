-- 0007: katalog dasar — categories & units (T2.1)
-- RLS per perintah: baca untuk member, tulis hanya owner/admin.
-- tenant_id immutable (trigger 0003), created_by/updated_at otomatis.

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  parent_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  constraint categories_parent_same_tenant
    foreign key (tenant_id, parent_id) references public.categories (tenant_id, id)
);

create index categories_parent_idx on public.categories (tenant_id, parent_id);

create table public.units (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, name)
);

alter table public.categories enable row level security;
alter table public.units enable row level security;

revoke all on public.categories from anon;
revoke all on public.units from anon;

create policy categories_select_member on public.categories
  for select to authenticated
  using (public.is_member(tenant_id));

create policy categories_insert_admin on public.categories
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));

create policy categories_update_admin on public.categories
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));

create policy categories_delete_admin on public.categories
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create policy units_select_member on public.units
  for select to authenticated
  using (public.is_member(tenant_id));

create policy units_insert_admin on public.units
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));

create policy units_update_admin on public.units
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));

create policy units_delete_admin on public.units
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create trigger categories_updated_at before update on public.categories
  for each row execute function public.set_updated_at();
create trigger units_updated_at before update on public.units
  for each row execute function public.set_updated_at();

create trigger categories_created_by before insert on public.categories
  for each row execute function public.set_created_by();
create trigger units_created_by before insert on public.units
  for each row execute function public.set_created_by();

create trigger categories_tenant_id_immutable before update on public.categories
  for each row execute function public.prevent_tenant_change();
create trigger units_tenant_id_immutable before update on public.units
  for each row execute function public.prevent_tenant_change();
