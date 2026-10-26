-- 0017: katalog layar kasir (T4.3)
-- Satu query untuk grid produk: harga tier/grosir dihitung server (resolve_price),
-- stok outlet, dan opsi satuan. cost_price/unit_cost sengaja TIDAK dikembalikan.

create function public.pos_catalog(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_tier_id uuid
) returns table (
  product_id uuid,
  name text,
  sku text,
  barcode text,
  base_unit_id uuid,
  base_unit_name text,
  price bigint,
  stock_qty numeric,
  min_stock numeric,
  is_low boolean,
  track_stock boolean,
  units jsonb
)
  language plpgsql
  stable
  security definer
  set search_path = public
  as $$
  begin
    if not public.is_member(p_tenant_id) then
      raise exception 'Tidak berhak membaca katalog tenant ini' using errcode = '42501';
    end if;
    if not exists (
      select 1 from public.outlets
      where tenant_id = p_tenant_id and id = p_outlet_id
    ) then
      raise exception 'Outlet tidak ditemukan' using errcode = 'P0001';
    end if;

    return query
    select
      p.id,
      p.name,
      p.sku,
      p.barcode,
      p.base_unit_id,
      bu.name,
      public.resolve_price(p_tenant_id, p.id, p.base_unit_id, p_tier_id, 1),
      coalesce(sl.qty_base, 0),
      p.min_stock,
      (p.track_stock and p.min_stock > 0 and coalesce(sl.qty_base, 0) < p.min_stock),
      p.track_stock,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'unit_id', x.unit_id,
          'name', x.unit_name,
          'factor', x.factor,
          'price', public.resolve_price(p_tenant_id, p.id, x.unit_id, p_tier_id, 1)
        ) order by x.factor, x.unit_name)
        from (
          select p.base_unit_id as unit_id, bu2.name as unit_name, 1::numeric as factor
          from public.units bu2
          where bu2.tenant_id = p_tenant_id and bu2.id = p.base_unit_id
          union all
          select pu.unit_id, u.name, pu.factor_to_base
          from public.product_units pu
          join public.units u
            on u.tenant_id = pu.tenant_id and u.id = pu.unit_id
          where pu.tenant_id = p_tenant_id and pu.product_id = p.id
        ) x
      ), '[]'::jsonb)
    from public.products p
    left join public.units bu
      on bu.tenant_id = p.tenant_id and bu.id = p.base_unit_id
    left join public.stock_levels sl
      on sl.tenant_id = p.tenant_id
     and sl.product_id = p.id
     and sl.outlet_id = p_outlet_id
    where p.tenant_id = p_tenant_id
      and p.active
    order by p.name;
  end;
  $$;

revoke execute on function public.pos_catalog(uuid, uuid, uuid) from public, anon;
grant execute on function public.pos_catalog(uuid, uuid, uuid) to authenticated;
