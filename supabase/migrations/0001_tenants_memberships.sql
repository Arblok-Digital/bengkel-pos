-- 0001: tenants, outlets, memberships + helper RLS (is_member, has_role)
-- Referensi desain: ARCHITECTURE.md Bagian 4.1 dan 4.11.

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  business_type text not null default 'both'
    check (business_type in ('bengkel', 'toko_bangunan', 'both')),
  settings jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);

create table public.outlets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null,
  address text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'kasir'
    check (role in ('owner', 'admin', 'kasir', 'mekanik', 'gudang')),
  outlet_ids uuid[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, user_id)
);

-- Helper: apakah user saat ini anggota aktif tenant t?
-- Security definer supaya policy RLS dapat membaca memberships tanpa rekursi.
create function public.is_member(t uuid) returns boolean
  language sql stable security definer set search_path = public
  as $$
    select exists (
      select 1
      from public.memberships m
      where m.tenant_id = t
        and m.user_id = auth.uid()
        and m.active
    );
  $$;

-- Helper: apakah user saat ini punya salah satu role di tenant t?
create function public.has_role(t uuid, roles text[]) returns boolean
  language sql stable security definer set search_path = public
  as $$
    select exists (
      select 1
      from public.memberships m
      where m.tenant_id = t
        and m.user_id = auth.uid()
        and m.active
        and m.role = any (roles)
    );
  $$;

-- updated_at otomatis
create function public.set_updated_at() returns trigger
  language plpgsql set search_path = public
  as $$
  begin
    new.updated_at = now();
    return new;
  end;
  $$;

create trigger tenants_updated_at before update on public.tenants
  for each row execute function public.set_updated_at();
create trigger outlets_updated_at before update on public.outlets
  for each row execute function public.set_updated_at();
create trigger memberships_updated_at before update on public.memberships
  for each row execute function public.set_updated_at();

-- created_by otomatis dari sesi saat ini
create function public.set_created_by() returns trigger
  language plpgsql set search_path = public
  as $$
  begin
    new.created_by = coalesce(new.created_by, auth.uid());
    return new;
  end;
  $$;

create trigger tenants_created_by before insert on public.tenants
  for each row execute function public.set_created_by();
create trigger outlets_created_by before insert on public.outlets
  for each row execute function public.set_created_by();
create trigger memberships_created_by before insert on public.memberships
  for each row execute function public.set_created_by();

-- RLS: aktif di semua tabel
alter table public.tenants enable row level security;
alter table public.outlets enable row level security;
alter table public.memberships enable row level security;

-- Policy tenant_isolation
create policy tenant_isolation on public.tenants
  for all using (public.is_member(id))
  with check (public.is_member(id));

create policy tenant_isolation on public.outlets
  for all using (public.is_member(tenant_id))
  with check (public.is_member(tenant_id));

create policy tenant_isolation on public.memberships
  for all using (public.is_member(tenant_id))
  with check (public.is_member(tenant_id) and has_role(tenant_id, array['owner', 'admin']));

-- Indeks berawalan tenant_id (aturan keras Bagian 3)
create index idx_memberships_tenant_user on public.memberships (tenant_id, user_id);
create index idx_memberships_user on public.memberships (user_id) where active;
create index idx_outlets_tenant on public.outlets (tenant_id);
