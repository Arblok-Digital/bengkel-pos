-- 0022: purchase_orders + purchase_order_items (T6.1)
-- PO ke supplier: status draft -> ordered, total dihitung server,
-- idempoten via client_uuid, stok belum disentuh (stok dipotong/dimasukkan di T6.2).

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  outlet_id uuid not null,
  po_no text not null,
  client_uuid uuid not null,
  supplier_id uuid not null,
  status text not null check (status in ('draft', 'ordered', 'partial', 'received', 'cancelled')),
  total bigint not null check (total >= 0),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, client_uuid),
  unique (tenant_id, outlet_id, po_no),
  constraint po_outlet_same_tenant
    foreign key (tenant_id, outlet_id) references public.outlets (tenant_id, id),
  constraint po_supplier_same_tenant
    foreign key (tenant_id, supplier_id) references public.suppliers (tenant_id, id)
);

create index po_tenant_created_idx
  on public.purchase_orders (tenant_id, created_at desc);
create index po_tenant_supplier_idx
  on public.purchase_orders (tenant_id, supplier_id);
create index po_tenant_status_idx
  on public.purchase_orders (tenant_id, status);

create table public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  purchase_order_id uuid not null,
  product_id uuid not null,
  unit_id uuid not null,
  qty numeric not null check (qty > 0),
  qty_base numeric not null check (qty_base > 0),
  unit_price bigint not null check (unit_price >= 0),
  line_total bigint not null check (line_total >= 0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint poi_po_same_tenant
    foreign key (tenant_id, purchase_order_id) references public.purchase_orders (tenant_id, id) on delete cascade,
  constraint poi_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id),
  constraint poi_unit_same_tenant
    foreign key (tenant_id, unit_id) references public.units (tenant_id, id)
);

create index poi_po_idx
  on public.purchase_order_items (tenant_id, purchase_order_id);
create index poi_product_idx
  on public.purchase_order_items (tenant_id, product_id);

alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;

revoke all on public.purchase_orders from anon, authenticated;
revoke all on public.purchase_order_items from anon, authenticated;

grant select on public.purchase_orders to authenticated;
grant select on public.purchase_order_items to authenticated;

create policy po_select_member on public.purchase_orders
  for select to authenticated using (public.is_member(tenant_id));
create policy poi_select_member on public.purchase_order_items
  for select to authenticated using (public.is_member(tenant_id));

create trigger po_updated_at before update on public.purchase_orders
  for each row execute function public.set_updated_at();
create trigger po_created_by before insert on public.purchase_orders
  for each row execute function public.set_created_by();
create trigger po_tenant_id_immutable before update on public.purchase_orders
  for each row execute function public.prevent_tenant_change();

create trigger poi_created_by before insert on public.purchase_order_items
  for each row execute function public.set_created_by();
create trigger poi_tenant_id_immutable before update on public.purchase_order_items
  for each row execute function public.prevent_tenant_change();

-- Nomor PO: PO-YYYYMMDD-#### per outlet per hari.
create function public.generate_po_no(
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
      hashtextextended(p_tenant_id::text || ':po:' || p_outlet_id::text, 0)
    );

    select count(*) + 1 into v_seq
    from public.purchase_orders
    where tenant_id = p_tenant_id
      and outlet_id = p_outlet_id
      and created_at::date = current_date;

    return 'PO-' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(v_seq::text, 4, '0');
  end;
  $$;

revoke execute on function public.generate_po_no(uuid, uuid) from public, anon;
grant execute on function public.generate_po_no(uuid, uuid) to authenticated;

-- create_purchase_order: atomik + idempoten. Total dihitung server dari item.
create function public.create_purchase_order(
  p_client_uuid uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_supplier_id uuid,
  p_items jsonb,
  p_note text
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_po_id uuid;
    v_po record;
    v_item jsonb;
    v_lines jsonb := '[]'::jsonb;
    v_product record;
    v_unit_factor numeric;
    v_qty numeric;
    v_qty_base numeric;
    v_unit_price bigint;
    v_line_total bigint;
    v_total bigint := 0;
    v_po_no text;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk membuat PO' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    select id, po_no, total, status
      into v_po
    from public.purchase_orders
    where tenant_id = p_tenant_id and client_uuid = p_client_uuid;

    if v_po.id is not null then
      return jsonb_build_object(
        'purchase_order_id', v_po.id,
        'po_no', v_po.po_no,
        'total', v_po.total,
        'status', v_po.status,
        'idempotent', true
      );
    end if;

    if not public.has_role(p_tenant_id, array['owner', 'admin']) then
      raise exception 'Hanya owner/admin yang boleh membuat PO' using errcode = '42501';
    end if;

    if p_items is null or jsonb_typeof(p_items) <> 'array'
      or jsonb_array_length(p_items) = 0 then
      raise exception 'Minimal satu item PO' using errcode = 'P0001';
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

    for v_item in select * from jsonb_array_elements(p_items)
    loop
      v_qty := (v_item ->> 'qty')::numeric;
      v_unit_price := (v_item ->> 'unit_price')::bigint;

      if v_qty is null or v_qty <= 0 then
        raise exception 'Qty harus lebih dari 0' using errcode = 'P0001';
      end if;
      if v_unit_price is null or v_unit_price < 0 then
        raise exception 'Harga tidak boleh negatif' using errcode = 'P0001';
      end if;

      select id, base_unit_id into v_product
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
      v_line_total := round(v_qty * v_unit_price);
      if v_line_total < 0 then
        raise exception 'Total baris tidak boleh negatif' using errcode = 'P0001';
      end if;

      v_total := v_total + v_line_total;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'product_id', v_product.id,
        'unit_id', (v_item ->> 'unit_id')::uuid,
        'qty', v_qty,
        'qty_base', v_qty_base,
        'unit_price', v_unit_price,
        'line_total', v_line_total,
        'note', nullif(btrim(coalesce(v_item ->> 'note', '')), '')
      ));
    end loop;

    v_po_no := public.generate_po_no(p_tenant_id, p_outlet_id);

    insert into public.purchase_orders (
      tenant_id, outlet_id, po_no, client_uuid, supplier_id, status, total, note
    ) values (
      p_tenant_id, p_outlet_id, v_po_no, p_client_uuid, p_supplier_id,
      'draft', v_total,
      nullif(btrim(coalesce(p_note, '')), '')
    )
    returning id into v_po_id;

    for v_item in select * from jsonb_array_elements(v_lines)
    loop
      insert into public.purchase_order_items (
        tenant_id, purchase_order_id, product_id, unit_id, qty, qty_base,
        unit_price, line_total, note
      ) values (
        p_tenant_id, v_po_id, (v_item ->> 'product_id')::uuid,
        (v_item ->> 'unit_id')::uuid, (v_item ->> 'qty')::numeric,
        (v_item ->> 'qty_base')::numeric, (v_item ->> 'unit_price')::bigint,
        (v_item ->> 'line_total')::bigint, v_item ->> 'note'
      );
    end loop;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, after, user_id
    ) values (
      p_tenant_id, 'purchase_order', v_po_id, 'create',
      jsonb_build_object(
        'po_no', v_po_no,
        'supplier_id', p_supplier_id,
        'total', v_total,
        'status', 'draft'
      ),
      auth.uid()
    );

    return jsonb_build_object(
      'purchase_order_id', v_po_id,
      'po_no', v_po_no,
      'total', v_total,
      'status', 'draft',
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public.create_purchase_order(
  uuid, uuid, uuid, uuid, jsonb, text
) from public, anon;
grant execute on function public.create_purchase_order(
  uuid, uuid, uuid, uuid, jsonb, text
) to authenticated;
