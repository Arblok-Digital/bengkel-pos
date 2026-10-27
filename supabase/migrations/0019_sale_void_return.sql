-- 0019: void & retur penjualan (T4.6)
-- Void/retur hanya owner/admin + alasan wajib. Stok dikembalikan lewat movement
-- 'sale_return'. Dokumen penjualan tidak diedit; status berubah ke void atau
-- retur dicatat terpisah. Semua RPC idempoten via client_uuid.

alter table public.sales
  add column void_reason text,
  add column voided_at timestamptz,
  add column voided_by uuid,
  add column void_client_uuid uuid;

create unique index sales_void_client_uuid_key
  on public.sales (tenant_id, void_client_uuid)
  where void_client_uuid is not null;

create table public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  sale_id uuid not null,
  reason text not null check (btrim(reason) <> ''),
  client_uuid uuid not null,
  total bigint not null default 0 check (total >= 0),
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, client_uuid),
  constraint sale_returns_sale_same_tenant
    foreign key (tenant_id, sale_id)
    references public.sales (tenant_id, id)
);

create index sale_returns_sale_idx
  on public.sale_returns (tenant_id, sale_id, created_at desc);

create table public.sale_return_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  return_id uuid not null,
  sale_item_id uuid not null,
  product_id uuid not null,
  qty numeric not null check (qty > 0),
  qty_base numeric not null check (qty_base > 0),
  unit_price bigint not null check (unit_price >= 0),
  line_total bigint not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint sale_return_items_return_same_tenant
    foreign key (tenant_id, return_id)
    references public.sale_returns (tenant_id, id) on delete cascade,
  constraint sale_return_items_sale_item_same_tenant
    foreign key (tenant_id, sale_item_id)
    references public.sale_items (tenant_id, id),
  constraint sale_return_items_product_same_tenant
    foreign key (tenant_id, product_id)
    references public.products (tenant_id, id)
);

create index sale_return_items_return_idx
  on public.sale_return_items (tenant_id, return_id);
create index sale_return_items_sale_item_idx
  on public.sale_return_items (tenant_id, sale_item_id);

alter table public.sale_returns enable row level security;
alter table public.sale_return_items enable row level security;

revoke all on public.sale_returns from anon, authenticated;
revoke all on public.sale_return_items from anon, authenticated;
grant select on public.sale_returns to authenticated;
grant select on public.sale_return_items to authenticated;

create policy sale_returns_select_member on public.sale_returns
  for select to authenticated using (public.is_member(tenant_id));
create policy sale_return_items_select_member on public.sale_return_items
  for select to authenticated using (public.is_member(tenant_id));

create trigger sale_returns_created_by before insert on public.sale_returns
  for each row execute function public.set_created_by();
create trigger sale_returns_tenant_id_immutable before update on public.sale_returns
  for each row execute function public.prevent_tenant_change();

-- ═══════════════════════════════════════════════════════════════════════════════
-- Void penjualan
-- ═══════════════════════════════════════════════════════════════════════════════

create function public.void_sale(
  p_sale_id uuid,
  p_reason text,
  p_client_uuid uuid
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_sale public.sales;
    v_item record;
    v_reason text;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk void penjualan' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    select * into v_sale
    from public.sales
    where id = p_sale_id
    for update;

    if v_sale.id is null then
      raise exception 'Penjualan tidak ditemukan' using errcode = 'P0001';
    end if;
    if not public.has_role(v_sale.tenant_id, array['owner', 'admin']) then
      raise exception 'Tidak berhak void penjualan' using errcode = '42501';
    end if;

    if v_sale.status = 'void' then
      if v_sale.void_client_uuid = p_client_uuid then
        return jsonb_build_object(
          'sale_id', v_sale.id,
          'invoice_no', v_sale.invoice_no,
          'status', 'void',
          'idempotent', true
        );
      end if;
      raise exception 'Penjualan sudah di-void' using errcode = 'P0001';
    end if;

    v_reason := btrim(coalesce(p_reason, ''));
    if length(v_reason) < 3 then
      raise exception 'Alasan void wajib diisi (minimal 3 karakter)'
        using errcode = 'P0001';
    end if;

    if exists (
      select 1 from public.sale_returns
      where tenant_id = v_sale.tenant_id and sale_id = v_sale.id
    ) then
      raise exception 'Penjualan sudah memiliki retur, tidak bisa di-void'
        using errcode = 'P0001';
    end if;

    -- Stok kembali untuk produk yang melacak stok.
    for v_item in
      select si.product_id, si.qty_base, si.unit_cost, p.track_stock
      from public.sale_items si
      join public.products p
        on p.tenant_id = si.tenant_id and p.id = si.product_id
      where si.tenant_id = v_sale.tenant_id and si.sale_id = v_sale.id
    loop
      if v_item.track_stock then
        insert into public.stock_movements (
          tenant_id, product_id, outlet_id, qty_base, type, ref_type, ref_id,
          unit_cost, note
        ) values (
          v_sale.tenant_id, v_item.product_id, v_sale.outlet_id,
          v_item.qty_base, 'sale_return', 'sale_void', v_sale.id,
          v_item.unit_cost, 'Void ' || v_sale.invoice_no || ': ' || v_reason
        );
      end if;
    end loop;

    update public.sales
    set status = 'void',
        void_reason = v_reason,
        voided_at = now(),
        voided_by = auth.uid(),
        void_client_uuid = p_client_uuid
    where id = v_sale.id;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, before, after, reason, user_id
    ) values (
      v_sale.tenant_id, 'sale', v_sale.id, 'void',
      jsonb_build_object('status', v_sale.status),
      jsonb_build_object('status', 'void'),
      v_reason, auth.uid()
    );

    return jsonb_build_object(
      'sale_id', v_sale.id,
      'invoice_no', v_sale.invoice_no,
      'status', 'void',
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public.void_sale(uuid, text, uuid) from public, anon;
grant execute on function public.void_sale(uuid, text, uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- Retur sebagian
-- ═══════════════════════════════════════════════════════════════════════════════

create function public.create_sale_return(
  p_sale_id uuid,
  p_items jsonb,
  p_reason text,
  p_client_uuid uuid
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_sale public.sales;
    v_reason text;
    v_existing uuid;
    v_return_id uuid;
    v_total bigint := 0;
    v_item jsonb;
    v_sale_item public.sale_items;
    v_qty numeric;
    v_returned numeric;
    v_qty_base numeric;
    v_line_total bigint;
    v_track boolean;
    v_rows int := 0;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk retur penjualan' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    select * into v_sale
    from public.sales
    where id = p_sale_id
    for update;

    if v_sale.id is null then
      raise exception 'Penjualan tidak ditemukan' using errcode = 'P0001';
    end if;
    if not public.has_role(v_sale.tenant_id, array['owner', 'admin']) then
      raise exception 'Tidak berhak membuat retur' using errcode = '42501';
    end if;

    -- idempotensi
    select id into v_existing
    from public.sale_returns
    where tenant_id = v_sale.tenant_id and client_uuid = p_client_uuid;

    if v_existing is not null then
      return jsonb_build_object(
        'return_id', v_existing,
        'total', (select total from public.sale_returns where id = v_existing),
        'idempotent', true
      );
    end if;

    if v_sale.status = 'void' then
      raise exception 'Penjualan sudah di-void, tidak bisa diretur'
        using errcode = 'P0001';
    end if;

    v_reason := btrim(coalesce(p_reason, ''));
    if length(v_reason) < 3 then
      raise exception 'Alasan retur wajib diisi (minimal 3 karakter)'
        using errcode = 'P0001';
    end if;

    if p_items is null or jsonb_typeof(p_items) <> 'array'
      or jsonb_array_length(p_items) = 0 then
      raise exception 'Minimal satu item retur' using errcode = 'P0001';
    end if;

    insert into public.sale_returns (
      tenant_id, sale_id, reason, client_uuid
    ) values (
      v_sale.tenant_id, v_sale.id, v_reason, p_client_uuid
    )
    returning id into v_return_id;

    for v_item in select * from jsonb_array_elements(p_items)
    loop
      v_qty := (v_item ->> 'qty')::numeric;
      if v_qty is null or v_qty <= 0 then
        raise exception 'Qty retur harus lebih dari 0' using errcode = 'P0001';
      end if;

      select * into v_sale_item
      from public.sale_items
      where tenant_id = v_sale.tenant_id
        and sale_id = v_sale.id
        and id = (v_item ->> 'sale_item_id')::uuid;

      if v_sale_item.id is null then
        raise exception 'Item penjualan tidak ditemukan' using errcode = 'P0001';
      end if;

      select coalesce(sum(qty), 0) into v_returned
      from public.sale_return_items
      where tenant_id = v_sale.tenant_id
        and sale_item_id = v_sale_item.id;

      if v_qty > v_sale_item.qty - v_returned + 1e-9 then
        raise exception 'Qty retur melebihi sisa (terjual %, sudah retur %)',
          v_sale_item.qty, v_returned
          using errcode = 'P0001';
      end if;

      v_qty_base := round(
        v_qty * (v_sale_item.qty_base / v_sale_item.qty), 3
      );
      v_line_total := round(
        (v_qty / v_sale_item.qty) * v_sale_item.line_total
      );

      insert into public.sale_return_items (
        tenant_id, return_id, sale_item_id, product_id, qty, qty_base,
        unit_price, line_total
      ) values (
        v_sale.tenant_id, v_return_id, v_sale_item.id, v_sale_item.product_id,
        v_qty, v_qty_base, v_sale_item.unit_price, v_line_total
      );

      select track_stock into v_track
      from public.products
      where tenant_id = v_sale.tenant_id and id = v_sale_item.product_id;

      if v_track then
        insert into public.stock_movements (
          tenant_id, product_id, outlet_id, qty_base, type, ref_type, ref_id,
          unit_cost, note
        ) values (
          v_sale.tenant_id, v_sale_item.product_id, v_sale.outlet_id,
          v_qty_base, 'sale_return', 'sale_return', v_return_id,
          v_sale_item.unit_cost,
          'Retur ' || v_sale.invoice_no || ': ' || v_reason
        );
      end if;

      v_total := v_total + v_line_total;
      v_rows := v_rows + 1;
    end loop;

    update public.sale_returns set total = v_total where id = v_return_id;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, after, reason, user_id
    ) values (
      v_sale.tenant_id, 'sale', v_sale.id, 'return',
      jsonb_build_object('return_id', v_return_id, 'total', v_total, 'items', v_rows),
      v_reason, auth.uid()
    );

    return jsonb_build_object(
      'return_id', v_return_id,
      'total', v_total,
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public.create_sale_return(uuid, jsonb, text, uuid)
  from public, anon;
grant execute on function public.create_sale_return(uuid, jsonb, text, uuid)
  to authenticated;
