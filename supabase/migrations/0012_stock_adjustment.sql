-- 0012: penyesuaian stok manual (T3.2)
-- RPC atomik + idempoten (client_uuid). Stok tetap hanya berubah lewat movement.

alter table public.stock_movements
  add column client_uuid uuid;

create unique index stock_movements_tenant_client_uuid_key
  on public.stock_movements (tenant_id, client_uuid)
  where client_uuid is not null;

create function public.adjust_stock(
  p_tenant_id uuid,
  p_product_id uuid,
  p_outlet_id uuid,
  p_qty_base numeric,
  p_reason text,
  p_client_uuid uuid
) returns uuid
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_id uuid;
    v_track boolean;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk menyesuaikan stok' using errcode = '28000';
    end if;

    if not public.has_role(p_tenant_id, array['owner', 'admin']) then
      raise exception 'Tidak berhak menyesuaikan stok' using errcode = '42501';
    end if;

    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;
    if p_qty_base is null or p_qty_base = 0 then
      raise exception 'Qty penyesuaian tidak boleh 0' using errcode = 'P0001';
    end if;
    if p_reason is null or length(btrim(p_reason)) < 3 then
      raise exception 'Alasan penyesuaian wajib diisi (minimal 3 karakter)' using errcode = 'P0001';
    end if;

    select track_stock into v_track
    from public.products
    where tenant_id = p_tenant_id and id = p_product_id;

    if v_track is null then
      raise exception 'Produk tidak ditemukan' using errcode = 'P0001';
    end if;
    if not v_track then
      raise exception 'Produk ini tidak melacak stok' using errcode = 'P0001';
    end if;

    if not exists (
      select 1 from public.outlets
      where tenant_id = p_tenant_id and id = p_outlet_id
    ) then
      raise exception 'Outlet tidak ditemukan' using errcode = 'P0001';
    end if;

    -- idempotensi
    select id into v_id
    from public.stock_movements
    where tenant_id = p_tenant_id and client_uuid = p_client_uuid;

    if v_id is not null then
      return v_id;
    end if;

    begin
      insert into public.stock_movements (
        tenant_id, product_id, outlet_id, qty_base, type, note, client_uuid
      ) values (
        p_tenant_id, p_product_id, p_outlet_id, p_qty_base,
        'adjustment', btrim(p_reason), p_client_uuid
      )
      returning id into v_id;
    exception when unique_violation then
      select id into v_id
      from public.stock_movements
      where tenant_id = p_tenant_id and client_uuid = p_client_uuid;
    end;

    return v_id;
  end;
  $$;

revoke execute on function public.adjust_stock(uuid, uuid, uuid, numeric, text, uuid)
  from public, anon;
grant execute on function public.adjust_stock(uuid, uuid, uuid, numeric, text, uuid)
  to authenticated;
