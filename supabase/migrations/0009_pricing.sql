-- 0009: konversi satuan + tier harga + harga grosir (T2.3)
-- product_units: satuan tambahan per produk (1 sak = 40 kg)
-- price_tiers: daftar tier per tenant (default dibuat otomatis)
-- product_prices: harga per tier/unit
-- price_breaks: harga grosir berdasarkan qty
-- resolve_price(): harga final = harga tier, lalu harga grosir terendah yang berlaku.

create table public.price_tiers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, name),
  unique (tenant_id, id)
);

create table public.product_units (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  product_id uuid not null,
  unit_id uuid not null,
  factor_to_base numeric not null check (factor_to_base > 0),
  sell_price bigint not null default 0 check (sell_price >= 0),
  barcode text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, product_id, unit_id),
  unique (tenant_id, id),
  constraint product_units_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id) on delete cascade,
  constraint product_units_unit_same_tenant
    foreign key (tenant_id, unit_id) references public.units (tenant_id, id)
);

create table public.product_prices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  product_id uuid not null,
  tier_id uuid not null,
  unit_id uuid not null,
  price bigint not null check (price >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, product_id, tier_id, unit_id),
  constraint product_prices_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id) on delete cascade,
  constraint product_prices_tier_same_tenant
    foreign key (tenant_id, tier_id) references public.price_tiers (tenant_id, id) on delete cascade,
  constraint product_prices_unit_same_tenant
    foreign key (tenant_id, unit_id) references public.units (tenant_id, id)
);

create table public.price_breaks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  product_id uuid not null,
  unit_id uuid not null,
  min_qty numeric not null check (min_qty > 0),
  price bigint not null check (price >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, product_id, unit_id, min_qty),
  constraint price_breaks_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id) on delete cascade,
  constraint price_breaks_unit_same_tenant
    foreign key (tenant_id, unit_id) references public.units (tenant_id, id)
);

create index product_units_product_idx on public.product_units (tenant_id, product_id);
create index product_prices_product_idx on public.product_prices (tenant_id, product_id);
create index price_breaks_product_idx on public.price_breaks (tenant_id, product_id);
create index price_tiers_tenant_idx on public.price_tiers (tenant_id, name);

alter table public.price_tiers enable row level security;
alter table public.product_units enable row level security;
alter table public.product_prices enable row level security;
alter table public.price_breaks enable row level security;

revoke all on public.price_tiers from anon;
revoke all on public.product_units from anon;
revoke all on public.product_prices from anon;
revoke all on public.price_breaks from anon;

-- RLS: baca member, tulis owner/admin (pola sama seperti tabel lain)
create policy price_tiers_select_member on public.price_tiers
  for select to authenticated using (public.is_member(tenant_id));
create policy price_tiers_insert_admin on public.price_tiers
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy price_tiers_update_admin on public.price_tiers
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy price_tiers_delete_admin on public.price_tiers
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create policy product_units_select_member on public.product_units
  for select to authenticated using (public.is_member(tenant_id));
create policy product_units_insert_admin on public.product_units
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy product_units_update_admin on public.product_units
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy product_units_delete_admin on public.product_units
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create policy product_prices_select_member on public.product_prices
  for select to authenticated using (public.is_member(tenant_id));
create policy product_prices_insert_admin on public.product_prices
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy product_prices_update_admin on public.product_prices
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy product_prices_delete_admin on public.product_prices
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create policy price_breaks_select_member on public.price_breaks
  for select to authenticated using (public.is_member(tenant_id));
create policy price_breaks_insert_admin on public.price_breaks
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy price_breaks_update_admin on public.price_breaks
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy price_breaks_delete_admin on public.price_breaks
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

-- trigger umum
create trigger price_tiers_updated_at before update on public.price_tiers
  for each row execute function public.set_updated_at();
create trigger product_units_updated_at before update on public.product_units
  for each row execute function public.set_updated_at();
create trigger product_prices_updated_at before update on public.product_prices
  for each row execute function public.set_updated_at();
create trigger price_breaks_updated_at before update on public.price_breaks
  for each row execute function public.set_updated_at();

create trigger price_tiers_created_by before insert on public.price_tiers
  for each row execute function public.set_created_by();
create trigger product_units_created_by before insert on public.product_units
  for each row execute function public.set_created_by();
create trigger product_prices_created_by before insert on public.product_prices
  for each row execute function public.set_created_by();
create trigger price_breaks_created_by before insert on public.price_breaks
  for each row execute function public.set_created_by();

create trigger price_tiers_tenant_id_immutable before update on public.price_tiers
  for each row execute function public.prevent_tenant_change();
create trigger product_units_tenant_id_immutable before update on public.product_units
  for each row execute function public.prevent_tenant_change();
create trigger product_prices_tenant_id_immutable before update on public.product_prices
  for each row execute function public.prevent_tenant_change();
create trigger price_breaks_tenant_id_immutable before update on public.price_breaks
  for each row execute function public.prevent_tenant_change();

-- Tier default untuk tenant baru + backfill tenant yang sudah ada
create function public.seed_default_price_tiers() returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
  begin
    insert into public.price_tiers (tenant_id, name) values
      (new.id, 'Umum'),
      (new.id, 'Langganan'),
      (new.id, 'Kontraktor'),
      (new.id, 'Bengkel Partner')
    on conflict (tenant_id, name) do nothing;
    return new;
  end;
  $$;

revoke execute on function public.seed_default_price_tiers() from public, anon, authenticated;

create trigger tenants_default_price_tiers after insert on public.tenants
  for each row execute function public.seed_default_price_tiers();

insert into public.price_tiers (tenant_id, name)
select t.id, v.name
from public.tenants t
cross join (values ('Umum'), ('Langganan'), ('Kontraktor'), ('Bengkel Partner')) as v(name)
on conflict (tenant_id, name) do nothing;

-- Harga final: tier/unit -> harga satuan tambahan -> harga base produk.
-- Lalu ambil harga grosir terendah yang min_qty-nya terpenuhi.
create function public.resolve_price(
  p_tenant_id uuid,
  p_product_id uuid,
  p_unit_id uuid,
  p_tier_id uuid,
  p_qty numeric
) returns bigint
  language plpgsql
  stable
  security definer
  set search_path = public
  as $$
  declare
    v_price bigint;
    v_factor numeric;
    v_base_price bigint;
    v_base_unit uuid;
    v_break bigint;
  begin
    if not public.is_member(p_tenant_id) then
      raise exception 'Tidak berhak membaca harga tenant ini' using errcode = '42501';
    end if;
    if p_qty is null or p_qty <= 0 then
      raise exception 'qty harus lebih dari 0' using errcode = 'P0001';
    end if;

    select base_unit_id, sell_price into v_base_unit, v_base_price
    from public.products
    where tenant_id = p_tenant_id and id = p_product_id;

    if v_base_unit is null then
      raise exception 'Produk tidak ditemukan' using errcode = 'P0001';
    end if;

    -- 1) harga satuan tambahan (jika ada)
    select sell_price, factor_to_base into v_price, v_factor
    from public.product_units
    where tenant_id = p_tenant_id and product_id = p_product_id and unit_id = p_unit_id;

    -- 2) harga base (unit sama dengan base, atau fallback konversi)
    if v_base_unit = p_unit_id then
      v_price := coalesce(v_price, v_base_price);
    elsif v_price is null then
      if v_factor is null then
        raise exception 'Satuan tidak terdaftar untuk produk ini' using errcode = 'P0001';
      end if;
      v_price := round(v_base_price * v_factor);
    end if;

    -- 3) harga tier (menang atas harga satuan)
    if p_tier_id is not null then
      select pp.price into v_price
      from public.product_prices pp
      where pp.tenant_id = p_tenant_id
        and pp.product_id = p_product_id
        and pp.tier_id = p_tier_id
        and pp.unit_id = p_unit_id;

      -- jika tier tidak punya harga untuk unit ini, tetap pakai harga satuan
      if v_price is null then
        select sell_price into v_price
        from public.product_units
        where tenant_id = p_tenant_id and product_id = p_product_id and unit_id = p_unit_id;
        v_price := coalesce(v_price, v_base_price);
      end if;
    end if;

    -- 4) harga grosir: ambil yang terendah di antara break yang berlaku
    select min(price) into v_break
    from public.price_breaks
    where tenant_id = p_tenant_id
      and product_id = p_product_id
      and unit_id = p_unit_id
      and min_qty <= p_qty;

    if v_break is not null then
      v_price := least(v_price, v_break);
    end if;

    return v_price;
  end;
  $$;

revoke execute on function public.resolve_price(uuid, uuid, uuid, uuid, numeric) from public, anon;
grant execute on function public.resolve_price(uuid, uuid, uuid, uuid, numeric) to authenticated;
