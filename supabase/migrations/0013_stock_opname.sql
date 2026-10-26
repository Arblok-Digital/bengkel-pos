-- 0013: stok opname (T3.3)
-- Draft opname menyalin system_qty per produk/outlet. Saat posting, selisih
-- dihitung terhadap stok terkini dan dicatat sebagai satu movement 'opname'.

create table public.stock_opnames (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  outlet_id uuid not null,
  status text not null default 'draft'
    check (status in ('draft', 'posted', 'cancelled')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  posted_at timestamptz,
  posted_by uuid,
  unique (tenant_id, id),
  constraint stock_opnames_outlet_same_tenant
    foreign key (tenant_id, outlet_id) references public.outlets (tenant_id, id)
);

create index stock_opnames_tenant_idx
  on public.stock_opnames (tenant_id, created_at desc);

create table public.stock_opname_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  opname_id uuid not null,
  product_id uuid not null,
  system_qty numeric not null default 0,
  counted_qty numeric,
  difference numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (tenant_id, opname_id, product_id),
  constraint stock_opname_items_opname_same_tenant
    foreign key (tenant_id, opname_id)
    references public.stock_opnames (tenant_id, id) on delete cascade,
  constraint stock_opname_items_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id)
);

create index stock_opname_items_opname_idx
  on public.stock_opname_items (tenant_id, opname_id);

alter table public.stock_opnames enable row level security;
alter table public.stock_opname_items enable row level security;

revoke all on public.stock_opnames from anon, authenticated;
revoke all on public.stock_opname_items from anon, authenticated;
grant select on public.stock_opnames to authenticated;
grant select on public.stock_opname_items to authenticated;

create policy stock_opnames_select_member on public.stock_opnames
  for select to authenticated using (public.is_member(tenant_id));
create policy stock_opname_items_select_member on public.stock_opname_items
  for select to authenticated using (public.is_member(tenant_id));

create trigger stock_opnames_updated_at before update on public.stock_opnames
  for each row execute function public.set_updated_at();
create trigger stock_opnames_created_by before insert on public.stock_opnames
  for each row execute function public.set_created_by();
create trigger stock_opnames_tenant_id_immutable before update on public.stock_opnames
  for each row execute function public.prevent_tenant_change();

-- Buat draft opname: salin semua produk aktif yang melacak stok
create function public.create_stock_opname(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_note text
) returns uuid
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_id uuid;
  begin
    if auth.uid() is null then
      raise exception 'Harus login' using errcode = '28000';
    end if;
    if not public.has_role(p_tenant_id, array['owner', 'admin']) then
      raise exception 'Tidak berhak membuat opname stok' using errcode = '42501';
    end if;
    if not exists (
      select 1 from public.outlets
      where tenant_id = p_tenant_id and id = p_outlet_id
    ) then
      raise exception 'Outlet tidak ditemukan' using errcode = 'P0001';
    end if;

    insert into public.stock_opnames (tenant_id, outlet_id, note)
    values (p_tenant_id, p_outlet_id, nullif(btrim(p_note), ''))
    returning id into v_id;

    insert into public.stock_opname_items (
      tenant_id, opname_id, product_id, system_qty
    )
    select
      p_tenant_id,
      v_id,
      p.id,
      coalesce(sl.qty_base, 0)
    from public.products p
    left join public.stock_levels sl
      on sl.tenant_id = p.tenant_id
     and sl.product_id = p.id
     and sl.outlet_id = p_outlet_id
    where p.tenant_id = p_tenant_id
      and p.track_stock
      and p.active;

    return v_id;
  end;
  $$;

revoke execute on function public.create_stock_opname(uuid, uuid, text)
  from public, anon;
grant execute on function public.create_stock_opname(uuid, uuid, text)
  to authenticated;

-- Simpan hitungan (bulk). p_counts = [{"item_id":"...","counted_qty":8}, ...]
create function public.save_stock_opname_counts(
  p_opname_id uuid,
  p_counts jsonb
) returns integer
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_tenant uuid;
    v_status text;
    v_item jsonb;
    v_count int := 0;
    v_qty numeric;
  begin
    select tenant_id, status into v_tenant, v_status
    from public.stock_opnames
    where id = p_opname_id;

    if v_tenant is null then
      raise exception 'Opname tidak ditemukan' using errcode = 'P0001';
    end if;
    if not public.has_role(v_tenant, array['owner', 'admin']) then
      raise exception 'Tidak berhak menyimpan hitungan' using errcode = '42501';
    end if;
    if v_status <> 'draft' then
      raise exception 'Hanya opname draft yang bisa diubah' using errcode = 'P0001';
    end if;

    for v_item in select * from jsonb_array_elements(coalesce(p_counts, '[]'::jsonb))
    loop
      v_qty := (v_item ->> 'counted_qty')::numeric;
      if v_qty is null or v_qty < 0 then
        raise exception 'Qty hitung tidak boleh negatif' using errcode = 'P0001';
      end if;

      update public.stock_opname_items
      set counted_qty = v_qty
      where tenant_id = v_tenant
        and opname_id = p_opname_id
        and id = (v_item ->> 'item_id')::uuid;

      if found then
        v_count := v_count + 1;
      end if;
    end loop;

    return v_count;
  end;
  $$;

revoke execute on function public.save_stock_opname_counts(uuid, jsonb)
  from public, anon;
grant execute on function public.save_stock_opname_counts(uuid, jsonb)
  to authenticated;

-- Posting: bandingkan hitungan dengan stok terkini, catat movement 'opname'
create function public.post_stock_opname(p_opname_id uuid) returns integer
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_tenant uuid;
    v_outlet uuid;
    v_status text;
    v_note text;
    v_item record;
    v_current numeric;
    v_diff numeric;
    v_count int := 0;
    v_counted int := 0;
  begin
    select tenant_id, outlet_id, status, note
      into v_tenant, v_outlet, v_status, v_note
    from public.stock_opnames
    where id = p_opname_id
    for update;

    if v_tenant is null then
      raise exception 'Opname tidak ditemukan' using errcode = 'P0001';
    end if;
    if not public.has_role(v_tenant, array['owner', 'admin']) then
      raise exception 'Tidak berhak memposting opname' using errcode = '42501';
    end if;
    if v_status <> 'draft' then
      raise exception 'Hanya opname draft yang bisa diposting' using errcode = 'P0001';
    end if;

    for v_item in
      select id, product_id, counted_qty
      from public.stock_opname_items
      where tenant_id = v_tenant and opname_id = p_opname_id
      order by product_id
    loop
      continue when v_item.counted_qty is null;
      v_counted := v_counted + 1;

      select qty_base into v_current
      from public.stock_levels
      where tenant_id = v_tenant
        and product_id = v_item.product_id
        and outlet_id = v_outlet
      for update;

      v_current := coalesce(v_current, 0);
      v_diff := v_item.counted_qty - v_current;

      update public.stock_opname_items
      set system_qty = v_current,
          difference = v_diff
      where id = v_item.id;

      if v_diff <> 0 then
        insert into public.stock_movements (
          tenant_id, product_id, outlet_id, qty_base, type,
          ref_type, ref_id, note
        ) values (
          v_tenant, v_item.product_id, v_outlet, v_diff, 'opname',
          'stock_opname', p_opname_id,
          coalesce(v_note, 'Opname stok')
        );
        v_count := v_count + 1;
      end if;
    end loop;

    if v_counted = 0 then
      raise exception 'Belum ada item yang dihitung' using errcode = 'P0001';
    end if;

    update public.stock_opnames
    set status = 'posted', posted_at = now(), posted_by = auth.uid()
    where id = p_opname_id;

    return v_count;
  end;
  $$;

revoke execute on function public.post_stock_opname(uuid)
  from public, anon;
grant execute on function public.post_stock_opname(uuid)
  to authenticated;
