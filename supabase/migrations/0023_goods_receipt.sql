-- 0023: penerimaan barang (T6.2)
-- goods_receipts + goods_receipt_items. Posting → movement 'purchase' (stok
-- masuk), HPP rata-rata bergerak diupdate di products.cost_price, status PO
-- diperbarui. Stok hanya lewat stock_movements (tidak UPDATE stock_levels).

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  outlet_id uuid not null,
  gr_no text not null,
  client_uuid uuid not null,
  supplier_id uuid not null,
  purchase_order_id uuid,
  status text not null check (status in ('draft', 'received', 'cancelled')),
  total bigint not null check (total >= 0),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, client_uuid),
  unique (tenant_id, outlet_id, gr_no),
  constraint gr_outlet_same_tenant
    foreign key (tenant_id, outlet_id) references public.outlets (tenant_id, id),
  constraint gr_supplier_same_tenant
    foreign key (tenant_id, supplier_id) references public.suppliers (tenant_id, id),
  constraint gr_po_same_tenant
    foreign key (tenant_id, purchase_order_id) references public.purchase_orders (tenant_id, id)
);

create index gr_tenant_created_idx
  on public.goods_receipts (tenant_id, created_at desc);
create index gr_tenant_supplier_idx
  on public.goods_receipts (tenant_id, supplier_id);
create index gr_tenant_status_idx
  on public.goods_receipts (tenant_id, status);

create table public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  goods_receipt_id uuid not null,
  purchase_order_item_id uuid,
  product_id uuid not null,
  unit_id uuid not null,
  qty numeric not null check (qty > 0),
  qty_base numeric not null check (qty_base > 0),
  unit_cost bigint not null check (unit_cost >= 0),
  line_total bigint not null check (line_total >= 0),
  note text,
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  constraint gri_gr_same_tenant
    foreign key (tenant_id, goods_receipt_id) references public.goods_receipts (tenant_id, id) on delete cascade,
  constraint gri_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id),
  constraint gri_unit_same_tenant
    foreign key (tenant_id, unit_id) references public.units (tenant_id, id)
);

create index gri_gr_idx
  on public.goods_receipt_items (tenant_id, goods_receipt_id);
create index gri_product_idx
  on public.goods_receipt_items (tenant_id, product_id);

alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;

revoke all on public.goods_receipts from anon, authenticated;
revoke all on public.goods_receipt_items from anon, authenticated;

grant select on public.goods_receipts to authenticated;
grant select on public.goods_receipt_items to authenticated;

create policy gr_select_member on public.goods_receipts
  for select to authenticated using (public.is_member(tenant_id));
create policy gri_select_member on public.goods_receipt_items
  for select to authenticated using (public.is_member(tenant_id));

create trigger gr_updated_at before update on public.goods_receipts
  for each row execute function public.set_updated_at();
create trigger gr_created_by before insert on public.goods_receipts
  for each row execute function public.set_created_by();
create trigger gr_tenant_id_immutable before update on public.goods_receipts
  for each row execute function public.prevent_tenant_change();

create trigger gri_created_by before insert on public.goods_receipt_items
  for each row execute function public.set_created_by();
create trigger gri_tenant_id_immutable before update on public.goods_receipt_items
  for each row execute function public.prevent_tenant_change();

-- Nomor penerimaan: GR-YYYYMMDD-#### per outlet per hari.
create function public.generate_gr_no(
  p_tenant_id uuid,
  p_outlet_id uuid
) returns text
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_seq int;
  begin
    perform pg_advisory_xact_lock(
      hashtextextended(p_tenant_id::text || ':gr:' || p_outlet_id::text, 0)
    );

    select count(*) + 1 into v_seq
    from public.goods_receipts
    where tenant_id = p_tenant_id
      and outlet_id = p_outlet_id
      and created_at::date = current_date;

    return 'GR-' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(v_seq::text, 4, '0');
  end;
  $$;

revoke execute on function public.generate_gr_no(uuid, uuid) from public, anon;
grant execute on function public.generate_gr_no(uuid, uuid) to authenticated;

-- receive_goods: atomik + idempoten. HPP rata-rata bergerak.
create function public.receive_goods(
  p_client_uuid uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_supplier_id uuid,
  p_purchase_order_id uuid,
  p_items jsonb,
  p_note text
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_gr_id uuid;
    v_gr record;
    v_item jsonb;
    v_lines jsonb := '[]'::jsonb;
    v_product record;
    v_unit_factor numeric;
    v_qty numeric;
    v_qty_base numeric;
    v_unit_cost bigint;
    v_line_total bigint;
    v_total bigint := 0;
    v_gr_no text;
    v_old_qty numeric;
    v_old_cost bigint;
    v_new_cost numeric;
    v_po record;
    v_po_status text;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk menerima barang' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    select id, gr_no, total, status
      into v_gr
    from public.goods_receipts
    where tenant_id = p_tenant_id and client_uuid = p_client_uuid;

    if v_gr.id is not null then
      return jsonb_build_object(
        'goods_receipt_id', v_gr.id,
        'gr_no', v_gr.gr_no,
        'total', v_gr.total,
        'status', v_gr.status,
        'idempotent', true
      );
    end if;

    if not public.has_role(p_tenant_id, array['owner', 'admin']) then
      raise exception 'Hanya owner/admin yang boleh menerima barang' using errcode = '42501';
    end if;

    if p_items is null or jsonb_typeof(p_items) <> 'array'
      or jsonb_array_length(p_items) = 0 then
      raise exception 'Minimal satu item penerimaan' using errcode = 'P0001';
    end if;

    if not exists (
      select 1 from public.outlets
      where tenant_id = p_tenant_id and id = p_outlet_id
    ) then
      raise exception 'Outlet tidak ditemukan' using errcode = 'P0001';
    end if;

    if not exists (
      select 1 from public.suppliers
      where tenant_id = p_tenant_id and id = p_supplier_id and active
    ) then
      raise exception 'Supplier tidak ditemukan atau tidak aktif' using errcode = 'P0001';
    end if;

    -- Validasi PO opsional (harus ordered/partial, supplier sama).
    if p_purchase_order_id is not null then
      select supplier_id, status into v_po
      from public.purchase_orders
      where tenant_id = p_tenant_id and id = p_purchase_order_id;

      if not found then
        raise exception 'Purchase order tidak ditemukan' using errcode = 'P0001';
      end if;
      if v_po.status not in ('ordered', 'partial') then
        raise exception 'PO tidak dapat diterima (status %)', v_po.status
          using errcode = 'P0001';
      end if;
      if v_po.supplier_id is distinct from p_supplier_id then
        raise exception 'Supplier PO tidak cocok dengan supplier penerimaan'
          using errcode = 'P0001';
      end if;
    end if;

    for v_item in select * from jsonb_array_elements(p_items)
    loop
      v_qty := (v_item ->> 'qty')::numeric;
      v_unit_cost := (v_item ->> 'unit_cost')::bigint;

      if v_qty is null or v_qty <= 0 then
        raise exception 'Qty harus lebih dari 0' using errcode = 'P0001';
      end if;
      if v_unit_cost is null or v_unit_cost < 0 then
        raise exception 'Harga pokok tidak boleh negatif' using errcode = 'P0001';
      end if;

      select id, base_unit_id, cost_price into v_product
      from public.products
      where tenant_id = p_tenant_id
        and id = (v_item ->> 'product_id')::uuid
        and active;

      if not found then
        raise exception 'Produk tidak ditemukan atau tidak aktif' using errcode = 'P0001';
      end if;

      if (v_item ->> 'unit_id')::uuid = v_product.base_unit_id then
        v_unit_factor := 1;
      else
        select factor_to_base into v_unit_factor
        from public.product_units
        where tenant_id = p_tenant_id
          and product_id = v_product.id
          and unit_id = (v_item ->> 'unit_id')::uuid;

        if v_unit_factor is null then
          raise exception 'Satuan tidak terdaftar untuk produk %', v_product.name
            using errcode = 'P0001';
        end if;
      end if;

      v_qty_base := v_qty * v_unit_factor;
      v_line_total := round(v_qty * v_unit_cost);
      if v_line_total < 0 then
        raise exception 'Total baris tidak boleh negatif' using errcode = 'P0001';
      end if;

      v_total := v_total + v_line_total;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'purchase_order_item_id', nullif(v_item ->> 'purchaseOrderItemId', '')::uuid,
        'product_id', v_product.id,
        'unit_id', (v_item ->> 'unit_id')::uuid,
        'qty', v_qty,
        'qty_base', v_qty_base,
        'unit_cost', v_unit_cost,
        'line_total', v_line_total,
        'note', nullif(btrim(coalesce(v_item ->> 'note', '')), '')
      ));
    end loop;

    v_gr_no := public.generate_gr_no(p_tenant_id, p_outlet_id);

    insert into public.goods_receipts (
      tenant_id, outlet_id, gr_no, client_uuid, supplier_id,
      purchase_order_id, status, total, note
    ) values (
      p_tenant_id, p_outlet_id, v_gr_no, p_client_uuid, p_supplier_id,
      p_purchase_order_id, 'received', v_total,
      nullif(btrim(coalesce(p_note, '')), '')
    )
    returning id into v_gr_id;

    for v_item in select * from jsonb_array_elements(v_lines)
    loop
      insert into public.goods_receipt_items (
        tenant_id, goods_receipt_id, purchase_order_item_id, product_id,
        unit_id, qty, qty_base, unit_cost, line_total, note
      ) values (
        p_tenant_id, v_gr_id,
        (v_item ->> 'purchase_order_item_id')::uuid,
        (v_item ->> 'product_id')::uuid,
        (v_item ->> 'unit_id')::uuid,
        (v_item ->> 'qty')::numeric,
        (v_item ->> 'qty_base')::numeric,
        (v_item ->> 'unit_cost')::bigint,
        (v_item ->> 'line_total')::bigint,
        v_item ->> 'note'
      );

      -- Kunci produk untuk HPP rata-rata bergerak (hindari race condition).
      perform pg_advisory_xact_lock(
        hashtextextended(p_tenant_id::text || ':' || (v_item ->> 'product_id')::text, 0)
      );

      -- Stok awal + cost saat ini.
      select qty_base into v_old_qty
      from public.stock_levels
      where tenant_id = p_tenant_id
        and product_id = (v_item ->> 'product_id')::uuid
        and outlet_id = p_outlet_id;

      select cost_price into v_old_cost
      from public.products
      where tenant_id = p_tenant_id
        and id = (v_item ->> 'product_id')::uuid;

      v_old_qty := coalesce(v_old_qty, 0);
      v_old_cost := coalesce(v_old_cost, 0);

      -- HPP rata-rata bergerak.
      if v_old_qty + (v_item ->> 'qty_base')::numeric > 0 then
        v_new_cost := round(
          (v_old_qty * v_old_cost + (v_item ->> 'qty_base')::numeric * v_unit_cost)
          / nullif(v_old_qty + (v_item ->> 'qty_base')::numeric, 0)
        );
      else
        v_new_cost := v_unit_cost;
      end if;

      update public.products
      set cost_price = v_new_cost::bigint
      where tenant_id = p_tenant_id
        and id = (v_item ->> 'product_id')::uuid;

      -- Movement stok masuk (trigger apply_stock_movement update stock_levels).
      insert into public.stock_movements (
        tenant_id, product_id, outlet_id, qty_base, type, ref_type, ref_id,
        unit_cost, note
      ) values (
        p_tenant_id, (v_item ->> 'product_id')::uuid, p_outlet_id,
        (v_item ->> 'qty_base')::numeric, 'purchase', 'goods_receipt', v_gr_id,
        v_unit_cost, 'Penerimaan ' || v_gr_no
      );
    end loop;

    -- Perbarui status PO terkait (received/partial).
    if p_purchase_order_id is not null then
      select status into v_po_status
      from public.purchase_orders
      where tenant_id = p_tenant_id and id = p_purchase_order_id;

      -- Jika semua item PO sudah terpenuhi oleh penerimaan kumulatif → received,
      -- jika sebagian → partial.
      with po_items as (
        select product_id, unit_id, sum(qty_base) as po_qty_base
        from public.purchase_order_items
        where tenant_id = p_tenant_id and purchase_order_id = p_purchase_order_id
        group by product_id, unit_id
      ),
      received as (
        select product_id, unit_id, sum(qty_base) as gr_qty_base
        from public.goods_receipt_items gri
        join public.goods_receipts gr
          on gr.tenant_id = gri.tenant_id and gr.id = gri.goods_receipt_id
        where gri.tenant_id = p_tenant_id
          and gr.purchase_order_id = p_purchase_order_id
          and gr.status = 'received'
        group by gri.product_id, gri.unit_id
      )
      select case
        when count(*) = 0 then 'ordered'
        when bool_and(r.gr_qty_base >= p.po_qty_base) then 'received'
        else 'partial'
      end into v_po_status
      from po_items p
      left join received r
        on r.product_id = p.product_id and r.unit_id = p.unit_id;

      update public.purchase_orders
      set status = v_po_status
      where tenant_id = p_tenant_id and id = p_purchase_order_id;
    end if;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, after, user_id
    ) values (
      p_tenant_id, 'goods_receipt', v_gr_id, 'create',
      jsonb_build_object(
        'gr_no', v_gr_no,
        'supplier_id', p_supplier_id,
        'purchase_order_id', p_purchase_order_id,
        'total', v_total,
        'status', 'received'
      ),
      auth.uid()
    );

    return jsonb_build_object(
      'goods_receipt_id', v_gr_id,
      'gr_no', v_gr_no,
      'total', v_total,
      'status', 'received',
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public.receive_goods(
  uuid, uuid, uuid, uuid, uuid, jsonb, text
) from public, anon;
grant execute on function public.receive_goods(
  uuid, uuid, uuid, uuid, uuid, jsonb, text
) to authenticated;
