-- 0027: konversi work order menjadi penjualan (T7.3)
-- Konversi wajib atomik: item diambil dari snapshot WO, penjualan dibuat lewat
-- _sales_core (satu-satunya jalur stok), lalu WO ditautkan ke sale dan ditagih.

alter table public.work_orders
  add constraint work_orders_sale_same_tenant
    foreign key (tenant_id, sale_id) references public.sales (tenant_id, id);

create unique index work_orders_tenant_sale_idx
  on public.work_orders (tenant_id, sale_id)
  where sale_id is not null;

create function public.create_work_order_sale(
  p_work_order_id uuid,
  p_client_uuid uuid,
  p_payments jsonb,
  p_note text,
  p_shift_id uuid
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_work_order public.work_orders;
    v_existing_sale public.sales;
    v_items jsonb;
    v_result jsonb;
    v_sale_id uuid;
    v_item_total bigint;
    v_payment_count int;
    v_kredit_amount bigint;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk membuat penjualan work order'
        using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    select * into v_work_order
    from public.work_orders
    where id = p_work_order_id
    for update;

    if v_work_order.id is null then
      raise exception 'Work order tidak ditemukan' using errcode = 'P0001';
    end if;
    if not public.has_role(v_work_order.tenant_id, array['owner', 'admin', 'kasir']) then
      raise exception 'Tidak berhak membuat penjualan work order' using errcode = '42501';
    end if;

    -- Konversi yang sudah berhasil selalu mengembalikan nota yang sama.
    if v_work_order.sale_id is not null then
      select * into v_existing_sale
      from public.sales
      where tenant_id = v_work_order.tenant_id
        and id = v_work_order.sale_id;

      return jsonb_build_object(
        'sale_id', v_existing_sale.id,
        'invoice_no', v_existing_sale.invoice_no,
        'total', v_existing_sale.total,
        'paid_amount', v_existing_sale.paid_amount,
        'change_amount', v_existing_sale.change_amount,
        'status', v_existing_sale.status,
        'idempotent', true
      );
    end if;

    if v_work_order.status <> 'selesai' then
      raise exception 'Work order harus berstatus selesai sebelum ditagihkan'
        using errcode = 'P0001';
    end if;

    if p_payments is null or jsonb_typeof(p_payments) <> 'array'
      or jsonb_array_length(p_payments) = 0 then
      raise exception 'Minimal satu pembayaran' using errcode = 'P0001';
    end if;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'product_id', item.product_id,
          'unit_id', item.unit_id,
          'qty', item.qty,
          'unit_price', item.unit_price,
          'discount', 0,
          'note', item.note,
          'mechanic_id', v_work_order.mechanic_id
        ) order by item.created_at, item.id
      ),
      '[]'::jsonb
    ) into v_items
    from public.work_order_items item
    where item.tenant_id = v_work_order.tenant_id
      and item.work_order_id = v_work_order.id
      and item.product_id is not null
      and item.unit_id is not null;

    if jsonb_array_length(v_items) = 0 then
      raise exception 'Work order belum memiliki item untuk ditagihkan'
        using errcode = 'P0001';
    end if;

    -- Kredit/tempo tidak boleh memakai nominal bebas: piutang selalu sebesar
    -- total work order, jadi nominalnya harus sama dengan total item.
    select coalesce(sum(item.line_total), 0) into v_item_total
    from public.work_order_items item
    where item.tenant_id = v_work_order.tenant_id
      and item.work_order_id = v_work_order.id
      and item.product_id is not null
      and item.unit_id is not null;

    select count(*) into v_payment_count from jsonb_array_elements(p_payments);

    if exists (
      select 1 from jsonb_array_elements(p_payments) as payment
      where payment ->> 'method' = 'kredit_tempo'
    ) then
      if v_payment_count > 1 then
        raise exception 'Kredit/tempo tidak bisa digabung dengan pembayaran lain'
          using errcode = 'P0001';
      end if;

      v_kredit_amount := coalesce((p_payments -> 0 ->> 'amount')::bigint, 0);

      if v_kredit_amount <> v_item_total then
        raise exception 'Nominal kredit/tempo harus sama dengan total work order (%)',
          v_item_total
          using errcode = 'P0001';
      end if;
    end if;

    v_result := public._sales_core(
      p_client_uuid,
      v_work_order.tenant_id,
      v_work_order.outlet_id,
      v_work_order.customer_id,
      v_items,
      p_payments,
      p_shift_id,
      coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Penagihan ' || v_work_order.wo_no),
      v_work_order.vehicle_id,
      v_work_order.id,
      false,
      null
    );

    v_sale_id := (v_result ->> 'sale_id')::uuid;

    -- Tandai transaksi ini sebagai konversi resmi supaya trigger guard
    -- mengizinkan pengisian sale_id dan status ditagih.
    perform set_config('bengkel.wo_sale_convert', v_work_order.id::text, true);

    update public.work_orders
    set sale_id = v_sale_id,
        status = 'ditagih',
        updated_at = now()
    where id = v_work_order.id;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, before, after, user_id
    ) values (
      v_work_order.tenant_id,
      'work_order',
      v_work_order.id,
      'convert_to_sale',
      jsonb_build_object('status', v_work_order.status, 'sale_id', null),
      jsonb_build_object('status', 'ditagih', 'sale_id', v_sale_id),
      auth.uid()
    );

    return v_result || jsonb_build_object('work_order_id', v_work_order.id);
  end;
  $$;

revoke execute on function public.create_work_order_sale(uuid, uuid, jsonb, text, uuid)
  from public, anon;
grant execute on function public.create_work_order_sale(uuid, uuid, jsonb, text, uuid)
  to authenticated;

-- ════════════════════════════════════════════════════════════════════════════════
-- Guard: sale_id dan status 'ditagih' hanya boleh diisi lewat create_work_order_sale
-- ════════════════════════════════════════════════════════════════════════════════
-- RLS work_orders mengizinkan mekanik melakukan UPDATE langsung, jadi tanpa guard
-- ini penautan ke penjualan dan status ditagih bisa dipalsukan dari client.

create function public.work_orders_guard_sale() returns trigger
  language plpgsql
  set search_path = public
  as $$
  declare
    v_from_conversion boolean :=
      coalesce(current_setting('bengkel.wo_sale_convert', true), '') = old.id::text;
  begin
    if new.sale_id is distinct from old.sale_id and not v_from_conversion then
      raise exception 'sale_id work order hanya boleh diisi lewat konversi penjualan'
        using errcode = '42501';
    end if;

    if new.status = 'ditagih'
      and old.status is distinct from 'ditagih'
      and (not v_from_conversion or new.sale_id is null)
    then
      raise exception 'Status ditagih hanya bisa didapat lewat konversi penjualan'
        using errcode = '42501';
    end if;

    if new.sale_id is not null and new.status not in ('ditagih') then
      raise exception 'Work order yang sudah ditagih harus berstatus ditagih'
        using errcode = '42501';
    end if;

    return new;
  end;
  $$;

create trigger work_orders_guard_sale
  before update on public.work_orders
  for each row execute function public.work_orders_guard_sale();

-- update_work_order_status tidak boleh dipakai untuk menandai ditagih.
create or replace function public.update_work_order_status(
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

    if p_status = 'ditagih' then
      raise exception 'Status ditagih hanya bisa didapat lewat konversi penjualan'
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