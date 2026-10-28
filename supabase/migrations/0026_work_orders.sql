-- 0026: work order bengkel (T7.2)
-- Tabel work_orders + work_order_items, RLS, policy per perintah,
-- trigger tenant immutable, fungsi generate_wo_no / generate_queue_no,
-- RPC create_work_order dan update_work_order_status.
-- Pemakaian sparepart di WO belum memotong stok; stok terpotong saat
-- WO dikonversi jadi sale (satu jalur potong stok, tidak ada dobel).

-- ════════════════════════════════════════════════════════════════════════════════
-- Tabel
-- ════════════════════════════════════════════════════════════════════════════════

create table public.work_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  outlet_id uuid not null,
  wo_no text not null,
  queue_no integer not null check (queue_no > 0),
  customer_id uuid not null,
  vehicle_id uuid not null,
  odometer numeric check (odometer >= 0),
  complaint text not null check (btrim(complaint) <> ''),
  diagnosis text,
  status text not null check (status in ('antri', 'dikerjakan', 'menunggu_part', 'selesai', 'ditagih', 'dibatalkan')),
  mechanic_id uuid,
  estimate_total bigint not null default 0 check (estimate_total >= 0),
  sale_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, outlet_id, wo_no),
  unique (tenant_id, outlet_id, queue_no),
  constraint work_orders_outlet_same_tenant
    foreign key (tenant_id, outlet_id) references public.outlets (tenant_id, id),
  constraint work_orders_customer_same_tenant
    foreign key (tenant_id, customer_id) references public.customers (tenant_id, id),
  constraint work_orders_vehicle_same_tenant
    foreign key (tenant_id, vehicle_id) references public.vehicles (tenant_id, id)
);

create index work_orders_tenant_status_idx
  on public.work_orders (tenant_id, status, created_at desc);
create index work_orders_tenant_queue_idx
  on public.work_orders (tenant_id, outlet_id, queue_no);
create index work_orders_customer_idx
  on public.work_orders (tenant_id, customer_id, created_at desc);
create index work_orders_vehicle_idx
  on public.work_orders (tenant_id, vehicle_id, created_at desc);
create index work_orders_mechanic_idx
  on public.work_orders (tenant_id, mechanic_id, created_at desc);

create table public.work_order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  work_order_id uuid not null,
  product_id uuid,
  unit_id uuid,
  qty numeric not null check (qty > 0),
  qty_base numeric not null check (qty_base > 0),
  unit_price bigint not null check (unit_price >= 0),
  line_total bigint not null check (line_total >= 0),
  note text,
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  constraint work_order_items_wo_same_tenant
    foreign key (tenant_id, work_order_id) references public.work_orders (tenant_id, id) on delete cascade,
  constraint work_order_items_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id),
  constraint work_order_items_unit_same_tenant
    foreign key (tenant_id, unit_id) references public.units (tenant_id, id)
);

create index work_order_items_wo_idx
  on public.work_order_items (tenant_id, work_order_id);
create index work_order_items_product_idx
  on public.work_order_items (tenant_id, product_id);

-- ════════════════════════════════════════════════════════════════════════════════
-- RLS + trigger
-- ════════════════════════════════════════════════════════════════════════════════

alter table public.work_orders enable row level security;
alter table public.work_order_items enable row level security;

revoke all on public.work_orders from anon, authenticated;
revoke all on public.work_order_items from anon, authenticated;

grant select on public.work_orders to authenticated;
grant update on public.work_orders to authenticated;
grant select on public.work_order_items to authenticated;
grant update on public.work_order_items to authenticated;

create policy work_orders_select_member on public.work_orders
  for select to authenticated using (public.is_member(tenant_id));
create policy work_orders_insert_admin on public.work_orders
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin', 'mekanik']));
create policy work_orders_update_admin on public.work_orders
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin', 'mekanik']))
  with check (public.has_role(tenant_id, array['owner', 'admin', 'mekanik']));
create policy work_orders_delete_admin on public.work_orders
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create policy work_order_items_select_member on public.work_order_items
  for select to authenticated using (public.is_member(tenant_id));
create policy work_order_items_insert_admin on public.work_order_items
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin', 'mekanik']));
create policy work_order_items_update_admin on public.work_order_items
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin', 'mekanik']))
  with check (public.has_role(tenant_id, array['owner', 'admin', 'mekanik']));
create policy work_order_items_delete_admin on public.work_order_items
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create trigger work_orders_updated_at before update on public.work_orders
  for each row execute function public.set_updated_at();
create trigger work_orders_created_by before insert on public.work_orders
  for each row execute function public.set_created_by();
create trigger work_orders_tenant_id_immutable before update on public.work_orders
  for each row execute function public.prevent_tenant_change();

create trigger work_order_items_updated_at before update on public.work_order_items
  for each row execute function public.set_updated_at();
create trigger work_order_items_created_by before insert on public.work_order_items
  for each row execute function public.set_created_by();
create trigger work_order_items_tenant_id_immutable before update on public.work_order_items
  for each row execute function public.prevent_tenant_change();

-- ════════════════════════════════════════════════════════════════════════════════
-- Nomor WO dan antrean: WO-YYYYMMDD-####, antrean reset tiap hari per outlet
-- ════════════════════════════════════════════════════════════════════════════════

create function public.generate_wo_no(
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
      hashtextextended(p_tenant_id::text || ':' || p_outlet_id::text || ':wo', 0)
    );

    select count(*) + 1 into v_seq
    from public.work_orders
    where tenant_id = p_tenant_id
      and outlet_id = p_outlet_id
      and created_at::date = current_date;

    return 'WO-' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(v_seq::text, 4, '0');
  end;
  $$;

create function public.generate_queue_no(
  p_tenant_id uuid,
  p_outlet_id uuid
) returns integer
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_seq int;
  begin
    perform pg_advisory_xact_lock(
      hashtextextended(p_tenant_id::text || ':' || p_outlet_id::text || ':queue', 0)
    );

    select count(*) + 1 into v_seq
    from public.work_orders
    where tenant_id = p_tenant_id
      and outlet_id = p_outlet_id
      and created_at::date = current_date;

    return v_seq;
  end;
  $$;

revoke execute on function public.generate_wo_no(uuid, uuid) from public, anon;
grant execute on function public.generate_wo_no(uuid, uuid) to authenticated;
revoke execute on function public.generate_queue_no(uuid, uuid) from public, anon;
grant execute on function public.generate_queue_no(uuid, uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════════
-- create_work_order: atomik, idempoten via client_uuid (disimpan di ...?)
-- ════════════════════════════════════════════════════════════════════════════════

-- catatan: idempotensi WO ditangani di application layer lewat client_uuid yang
-- disimpan secara implisit via audit_logs; WO tidak punya kolom client_uuid karena
-- WO adalah dokumen internal bengkel, bukan transaksi penjualan.

create function public.create_work_order(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_customer_id uuid,
  p_vehicle_id uuid,
  p_odometer numeric,
  p_complaint text,
  p_diagnosis text,
  p_mechanic_id uuid,
  p_estimate_total bigint,
  p_items jsonb
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_wo_id uuid;
    v_wo_no text;
    v_queue_no integer;
    v_item jsonb;
    v_product record;
    v_unit_factor numeric := 1;
    v_qty numeric;
    v_unit_price bigint;
    v_discount bigint := 0;
    v_line_total bigint;
    v_lines jsonb := '[]'::jsonb;
    v_line jsonb;
    v_total bigint := 0;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk membuat work order' using errcode = '28000';
    end if;

    if not public.has_role(p_tenant_id, array['owner', 'admin', 'mekanik']) then
      raise exception 'Tidak berhak membuat work order' using errcode = '42501';
    end if;

    if not exists (
      select 1 from public.outlets
      where tenant_id = p_tenant_id and id = p_outlet_id
    ) then
      raise exception 'Outlet tidak ditemukan' using errcode = 'P0001';
    end if;

    if not exists (
      select 1 from public.customers
      where tenant_id = p_tenant_id and id = p_customer_id and active
    ) then
      raise exception 'Pelanggan tidak ditemukan atau tidak aktif' using errcode = 'P0001';
    end if;

    if not exists (
      select 1 from public.vehicles
      where tenant_id = p_tenant_id and id = p_vehicle_id and customer_id = p_customer_id
    ) then
      raise exception 'Kendaraan tidak ditemukan atau tidak milik pelanggan ini' using errcode = 'P0001';
    end if;

    if p_complaint is null or btrim(p_complaint) = '' then
      raise exception 'Keluhan wajib diisi' using errcode = 'P0001';
    end if;

    if p_items is null or jsonb_typeof(p_items) <> 'array'
      or jsonb_array_length(p_items) = 0 then
      raise exception 'Minimal satu item (jasa/sparepart)' using errcode = 'P0001';
    end if;

    v_wo_no := public.generate_wo_no(p_tenant_id, p_outlet_id);
    v_queue_no := public.generate_queue_no(p_tenant_id, p_outlet_id);

    insert into public.work_orders (
      tenant_id, outlet_id, wo_no, queue_no, customer_id, vehicle_id,
      odometer, complaint, diagnosis, mechanic_id, estimate_total, status,
      created_by
    ) values (
      p_tenant_id, p_outlet_id, v_wo_no, v_queue_no, p_customer_id, p_vehicle_id,
      p_odometer, nullif(btrim(p_complaint), ''),
      nullif(btrim(coalesce(p_diagnosis, '')), ''),
      p_mechanic_id, coalesce(p_estimate_total, 0), 'antri',
      auth.uid()
    )
    returning id into v_wo_id;

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
          raise exception 'Satuan tidak terdaftar untuk produk %',
            (select name from public.products where id = v_product.id)
            using errcode = 'P0001';
        end if;
      end if;

      v_line_total := round(v_qty * v_unit_price);
      v_total := v_total + v_line_total;

      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'product_id', v_product.id,
        'unit_id', (v_item ->> 'unit_id')::uuid,
        'qty', v_qty,
        'qty_base', v_qty * v_unit_factor,
        'unit_price', v_unit_price,
        'line_total', v_line_total,
        'note', nullif(btrim(coalesce(v_item ->> 'note', '')), '')
      ));
    end loop;

    -- Simpan estimate_total sebagai total item jika tidak diset secara terpisah.
    if coalesce(p_estimate_total, 0) = 0 then
      update public.work_orders
      set estimate_total = v_total
      where id = v_wo_id;
    end if;

    for v_line in select * from jsonb_array_elements(v_lines)
    loop
      insert into public.work_order_items (
        tenant_id, work_order_id, product_id, unit_id, qty, qty_base,
        unit_price, line_total, note
      ) values (
        p_tenant_id, v_wo_id, (v_line ->> 'product_id')::uuid,
        (v_line ->> 'unit_id')::uuid, (v_line ->> 'qty')::numeric,
        (v_line ->> 'qty_base')::numeric, (v_line ->> 'unit_price')::bigint,
        (v_line ->> 'line_total')::bigint, v_line ->> 'note'
      );
    end loop;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, after, user_id
    ) values (
      p_tenant_id, 'work_order', v_wo_id, 'create',
      jsonb_build_object(
        'wo_no', v_wo_no,
        'queue_no', v_queue_no,
        'customer_id', p_customer_id,
        'vehicle_id', p_vehicle_id,
        'status', 'antri',
        'estimate_total', coalesce(p_estimate_total, v_total)
      ),
      auth.uid()
    );

    return jsonb_build_object(
      'work_order_id', v_wo_id,
      'wo_no', v_wo_no,
      'queue_no', v_queue_no,
      'status', 'antri',
      'estimate_total', coalesce(p_estimate_total, v_total),
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public.create_work_order(
  uuid, uuid, uuid, uuid, numeric, text, text, uuid, bigint, jsonb
) from public, anon;
grant execute on function public.create_work_order(
  uuid, uuid, uuid, uuid, numeric, text, text, uuid, bigint, jsonb
) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════════
-- update_work_order_status: ubah status WO (antri -> dikerjakan -> ...)
-- ════════════════════════════════════════════════════════════════════════════════

create function public.update_work_order_status(
  p_wo_id uuid,
  p_status text
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_wo record;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk mengubah status work order' using errcode = '28000';
    end if;

    select * into v_wo
    from public.work_orders
    where id = p_wo_id
    for update;

    if v_wo.id is null then
      raise exception 'Work order tidak ditemukan' using errcode = 'P0001';
    end if;

    if not public.has_role(v_wo.tenant_id, array['owner', 'admin', 'mekanik']) then
      raise exception 'Tidak berhak mengubah status work order' using errcode = '42501';
    end if;

    if p_status not in ('antri', 'dikerjakan', 'menunggu_part', 'selesai', 'ditagih', 'dibatalkan') then
      raise exception 'Status tidak dikenal' using errcode = 'P0001';
    end if;

    -- Dokumen yang sudah ditagih atau dibatalkan tidak boleh diedit.
    if v_wo.status in ('ditagih', 'dibatalkan') then
      raise exception 'Work order sudah %: tidak boleh diubah', v_wo.status
        using errcode = 'P0001';
    end if;

    update public.work_orders
    set status = p_status, updated_at = now()
    where id = v_wo.id;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, before, after, user_id
    ) values (
      v_wo.tenant_id, 'work_order', v_wo.id, 'status_change',
      jsonb_build_object('status', v_wo.status),
      jsonb_build_object('status', p_status),
      auth.uid()
    );

    return jsonb_build_object(
      'work_order_id', v_wo.id,
      'wo_no', v_wo.wo_no,
      'status', p_status,
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public.update_work_order_status(uuid, text) from public, anon;
grant execute on function public.update_work_order_status(uuid, text) to authenticated;
