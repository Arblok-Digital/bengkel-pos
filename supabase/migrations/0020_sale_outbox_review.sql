-- 0020: outbox offline + status needs_review (T10.3)
--
-- Aturan:
-- - create_sale tetap ketat (dipakai saat online): konflik stok/harga ditolak.
-- - sync_sale dipakai replay outbox: konflik stok/harga TIDAK membuang transaksi.
--   Sale disimpan berstatus 'needs_review', tanpa potong stok dan tanpa piutang,
--   lalu diselesaikan pemilik lewat resolve_sale_review.
-- - Logika inti dipindah ke public._sales_core supaya create_sale dan sync_sale
--   tidak menduplikasi 300+ baris. Migrasi 0015 tidak diubah.

-- ═══════════════════════════════════════════════════════════════════════════════
-- Skema: status + kolom review
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.sales drop constraint sales_status_check;
alter table public.sales add constraint sales_status_check
  check (status in ('draft', 'paid', 'partial', 'credit', 'void', 'needs_review'));

alter table public.sales
  add column local_invoice_no text,
  add column needs_review_reason text,
  add column synced_at timestamptz,
  add column reviewed_at timestamptz,
  add column reviewed_by uuid;

comment on column public.sales.local_invoice_no is
  'Nomor sementara dari perangkat offline (TMP-<device>-<seq>).';
comment on column public.sales.needs_review_reason is
  'Alasan transaksi offline masuk needs_review (konflik stok/harga).';
comment on column public.sales.synced_at is
  'Waktu transaksi offline diterima server.';

create index sales_needs_review_idx
  on public.sales (tenant_id, sold_at desc)
  where status = 'needs_review';

-- ═══════════════════════════════════════════════════════════════════════════════
-- Pengaman: needs_review hanya boleh keluar status lewat resolve_sale_review
-- (void_sale biasa akan menambah stok yang tidak pernah dipotong).
-- ═══════════════════════════════════════════════════════════════════════════════

create function public.guard_sale_needs_review() returns trigger
  language plpgsql
  as $$
  begin
    if old.status = 'needs_review'
      and new.status <> 'needs_review'
      and coalesce(current_setting('bengkel.sale_review', true), '') <> 'on'
    then
      raise exception 'Transaksi berstatus perlu review: selesaikan lewat resolve_sale_review'
        using errcode = 'P0001';
    end if;
    return new;
  end;
  $$;

create trigger sales_needs_review_guard
  before update of status on public.sales
  for each row execute function public.guard_sale_needs_review();

-- ═══════════════════════════════════════════════════════════════════════════════
-- Inti penjualan (dipakai create_sale & sync_sale)
-- ═══════════════════════════════════════════════════════════════════════════════

create function public._sales_core(
  p_client_uuid uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_payments jsonb,
  p_shift_id uuid,
  p_note text,
  p_vehicle_id uuid,
  p_work_order_id uuid,
  p_offline boolean,
  p_local_invoice_no text
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_sale_id uuid;
    v_sale record;
    v_invoice_no text;
    v_subtotal bigint := 0;
    v_total bigint;
    v_paid bigint := 0;
    v_status text;
    v_change bigint := 0;
    v_item jsonb;
    v_line jsonb;
    v_lines jsonb := '[]'::jsonb;
    v_payment jsonb;
    v_product record;
    v_unit_factor numeric;
    v_expected_price bigint;
    v_unit_price bigint;
    v_discount bigint;
    v_line_total bigint;
    v_qty numeric;
    v_qty_base numeric;
    v_allow_negative boolean := false;
    v_current_stock numeric;
    v_tier_id uuid;
    v_credit_limit bigint;
    v_outstanding bigint;
    v_receivable bigint;
    v_shift record;
    v_review_reason text;
    v_needs_review boolean := false;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk membuat penjualan' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    -- Idempotensi: client_uuid sama mengembalikan sale yang sama.
    select id, invoice_no, total, paid_amount, change_amount, status,
           needs_review_reason
      into v_sale
    from public.sales
    where tenant_id = p_tenant_id and client_uuid = p_client_uuid;

    if v_sale.id is not null then
      return jsonb_build_object(
        'sale_id', v_sale.id,
        'invoice_no', v_sale.invoice_no,
        'total', v_sale.total,
        'paid_amount', v_sale.paid_amount,
        'change_amount', v_sale.change_amount,
        'status', v_sale.status,
        'needs_review_reason', v_sale.needs_review_reason,
        'idempotent', true
      );
    end if;

    if not public.has_role(p_tenant_id, array['owner', 'admin', 'kasir']) then
      raise exception 'Tidak berhak membuat penjualan' using errcode = '42501';
    end if;
    if p_items is null or jsonb_typeof(p_items) <> 'array'
      or jsonb_array_length(p_items) = 0 then
      raise exception 'Minimal satu item penjualan' using errcode = 'P0001';
    end if;
    if p_payments is null or jsonb_typeof(p_payments) <> 'array'
      or jsonb_array_length(p_payments) = 0 then
      raise exception 'Minimal satu pembayaran' using errcode = 'P0001';
    end if;

    if not exists (
      select 1 from public.outlets
      where tenant_id = p_tenant_id and id = p_outlet_id
    ) then
      raise exception 'Outlet tidak ditemukan' using errcode = 'P0001';
    end if;

    -- Shift (opsional): harus shift terbuka milik kasir ini (owner/admin boleh shift lain).
    if p_shift_id is not null then
      select cashier_id, closed_at into v_shift
      from public.cash_shifts
      where tenant_id = p_tenant_id and id = p_shift_id;

      if v_shift.cashier_id is null then
        raise exception 'Shift tidak ditemukan' using errcode = 'P0001';
      end if;
      if v_shift.closed_at is not null then
        raise exception 'Shift sudah ditutup' using errcode = 'P0001';
      end if;
      if v_shift.cashier_id <> auth.uid()
        and not public.has_role(p_tenant_id, array['owner', 'admin'])
      then
        raise exception 'Shift bukan milik kasir ini' using errcode = '42501';
      end if;
    end if;

    -- Pelanggan + tier (opsional)
    if p_customer_id is not null then
      select tier_id, credit_limit into v_tier_id, v_credit_limit
      from public.customers
      where tenant_id = p_tenant_id and id = p_customer_id and active;

      if not found then
        raise exception 'Pelanggan tidak ditemukan' using errcode = 'P0001';
      end if;
    end if;

    select coalesce((settings->>'allow_negative_stock')::boolean, false)
      into v_allow_negative
    from public.tenants
    where id = p_tenant_id;

    -- ─── Item: validasi stok + harga, hitung total di server ─────────────────
    for v_item in select * from jsonb_array_elements(p_items)
    loop
      v_qty := (v_item ->> 'qty')::numeric;
      v_unit_price := (v_item ->> 'unit_price')::bigint;
      v_discount := coalesce((v_item ->> 'discount')::bigint, 0);

      if v_qty is null or v_qty <= 0 then
        raise exception 'Qty harus lebih dari 0' using errcode = 'P0001';
      end if;
      if v_unit_price is null or v_unit_price < 0 then
        raise exception 'Harga tidak boleh negatif' using errcode = 'P0001';
      end if;
      if v_discount < 0 then
        raise exception 'Diskon tidak boleh negatif' using errcode = 'P0001';
      end if;

      select id, name, track_stock, cost_price, base_unit_id, sell_price
        into v_product
      from public.products
      where tenant_id = p_tenant_id
        and id = (v_item ->> 'product_id')::uuid
        and active;

      if not found then
        raise exception 'Produk tidak ditemukan atau tidak aktif' using errcode = 'P0001';
      end if;

      -- Konversi satuan: base = 1, selain itu harus terdaftar di product_units.
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

      -- Harga server: tier pelanggan + harga grosir. Client tidak boleh mengarang.
      v_expected_price := public.resolve_price(
        p_tenant_id, v_product.id, (v_item ->> 'unit_id')::uuid, v_tier_id, v_qty
      );

      if v_unit_price <> v_expected_price then
        if p_offline then
          -- Harga berubah sejak cache disimpan; transaksi tidak dibuang.
          v_needs_review := true;
          v_review_reason := concat_ws('; ', v_review_reason, format(
            'Harga %s berubah (dikirim %s, harga server %s)',
            v_product.name, v_unit_price, v_expected_price
          ));
        else
          raise exception 'Harga % tidak sesuai harga jual (seharusnya %)',
            v_product.name, v_expected_price
            using errcode = 'P0001';
        end if;
      end if;

      v_line_total := round(v_qty * v_unit_price) - v_discount;
      if v_line_total < 0 then
        raise exception 'Total baris tidak boleh negatif' using errcode = 'P0001';
      end if;

      -- Stok: kunci per produk+outlet supaya dua kasir tidak balapan.
      if v_product.track_stock then
        perform pg_advisory_xact_lock(
          hashtextextended(
            p_tenant_id::text || ':' || p_outlet_id::text || ':' || v_product.id::text,
            0
          )
        );

        select qty_base into v_current_stock
        from public.stock_levels
        where tenant_id = p_tenant_id
          and product_id = v_product.id
          and outlet_id = p_outlet_id
        for update;

        v_current_stock := coalesce(v_current_stock, 0);

        if not v_allow_negative and v_current_stock < v_qty_base then
          if p_offline then
            -- Server menang: stok tidak dipotong, pemilik yang memutuskan.
            v_needs_review := true;
            v_review_reason := concat_ws('; ', v_review_reason, format(
              'Stok %s tidak cukup (tersedia %s, dibutuhkan %s)',
              v_product.name, v_current_stock, v_qty_base
            ));
          else
            raise exception 'Stok % tidak cukup (tersedia %, dibutuhkan %)',
              v_product.name, v_current_stock, v_qty_base
              using errcode = 'P0001';
          end if;
        end if;
      end if;

      v_subtotal := v_subtotal + v_line_total;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'product_id', v_product.id,
        'unit_id', (v_item ->> 'unit_id')::uuid,
        'qty', v_qty,
        'qty_base', v_qty_base,
        'unit_price', v_unit_price,
        'unit_cost', coalesce(v_product.cost_price, 0),
        'discount', v_discount,
        'line_total', v_line_total,
        'note', nullif(btrim(coalesce(v_item ->> 'note', '')), ''),
        'mechanic_id', nullif(v_item ->> 'mechanic_id', '')::uuid,
        'track_stock', v_product.track_stock
      ));
    end loop;

    v_total := v_subtotal;

    -- ─── Pembayaran ──────────────────────────────────────────────────────────
    for v_payment in select * from jsonb_array_elements(p_payments)
    loop
      if (v_payment ->> 'method') not in ('tunai', 'transfer', 'qris', 'debit', 'kredit_tempo') then
        raise exception 'Metode pembayaran tidak dikenal' using errcode = 'P0001';
      end if;
      if coalesce((v_payment ->> 'amount')::bigint, 0) <= 0 then
        raise exception 'Nominal pembayaran harus lebih dari 0' using errcode = 'P0001';
      end if;
      if (v_payment ->> 'method') <> 'kredit_tempo' then
        v_paid := v_paid + (v_payment ->> 'amount')::bigint;
      end if;
    end loop;

    if v_paid > v_total then
      v_change := v_paid - v_total;
      v_paid := v_total;
    end if;

    if v_paid < v_total and p_customer_id is null then
      raise exception 'Pembayaran kurang dari total: wajib pilih pelanggan untuk kredit'
        using errcode = 'P0001';
    end if;

    v_status := case
      when v_paid >= v_total then 'paid'
      when v_paid > 0 then 'partial'
      else 'credit'
    end;

    if v_needs_review then
      v_status := 'needs_review';
    end if;

    -- ─── Insert sale ─────────────────────────────────────────────────────────
    v_invoice_no := public.generate_invoice_no(p_tenant_id, p_outlet_id);

    insert into public.sales (
      tenant_id, outlet_id, invoice_no, local_invoice_no, client_uuid,
      customer_id, vehicle_id, work_order_id, status, subtotal, discount,
      tax, total, paid_amount, change_amount, cashier_id, shift_id, note,
      needs_review_reason, synced_at
    ) values (
      p_tenant_id, p_outlet_id, v_invoice_no,
      nullif(btrim(coalesce(p_local_invoice_no, '')), ''),
      p_client_uuid, p_customer_id, p_vehicle_id, p_work_order_id, v_status,
      v_subtotal, 0, 0, v_total, v_paid, v_change, auth.uid(), p_shift_id,
      nullif(btrim(coalesce(p_note, '')), ''),
      case when v_needs_review then v_review_reason end,
      case when p_offline then now() end
    )
    returning id into v_sale_id;

    -- ─── Item + movement ─────────────────────────────────────────────────────
    for v_line in select * from jsonb_array_elements(v_lines)
    loop
      insert into public.sale_items (
        tenant_id, sale_id, product_id, unit_id, qty, qty_base, unit_price,
        unit_cost, discount, line_total, note, mechanic_id
      ) values (
        p_tenant_id, v_sale_id, (v_line ->> 'product_id')::uuid,
        (v_line ->> 'unit_id')::uuid, (v_line ->> 'qty')::numeric,
        (v_line ->> 'qty_base')::numeric, (v_line ->> 'unit_price')::bigint,
        (v_line ->> 'unit_cost')::bigint, (v_line ->> 'discount')::bigint,
        (v_line ->> 'line_total')::bigint, v_line ->> 'note',
        (v_line ->> 'mechanic_id')::uuid
      );

      -- Stok tidak dipotong saat needs_review; dipotong ketika pemilik menyetujui.
      if not v_needs_review and (v_line ->> 'track_stock')::boolean then
        insert into public.stock_movements (
          tenant_id, product_id, outlet_id, qty_base, type, ref_type, ref_id,
          unit_cost, note
        ) values (
          p_tenant_id, (v_line ->> 'product_id')::uuid, p_outlet_id,
          -((v_line ->> 'qty_base')::numeric), 'sale', 'sale', v_sale_id,
          (v_line ->> 'unit_cost')::bigint, 'Penjualan ' || v_invoice_no
        );
      end if;
    end loop;

    -- ─── Payments ────────────────────────────────────────────────────────────
    for v_payment in select * from jsonb_array_elements(p_payments)
    loop
      insert into public.payments (
        tenant_id, sale_id, method, amount, reference
      ) values (
        p_tenant_id, v_sale_id, v_payment ->> 'method',
        (v_payment ->> 'amount')::bigint,
        nullif(btrim(coalesce(v_payment ->> 'reference', '')), '')
      );
    end loop;

    -- ─── Piutang + limit kredit (ditunda saat needs_review) ──────────────────
    if not v_needs_review and v_paid < v_total then
      v_receivable := v_total - v_paid;

      -- credit_limit 0 = tanpa batas (pemilik tidak mengisi limit).
      if coalesce(v_credit_limit, 0) > 0 then
        select coalesce(sum(amount), 0) into v_outstanding
        from public.receivables
        where tenant_id = p_tenant_id
          and customer_id = p_customer_id
          and status in ('open', 'partial');

        if v_outstanding + v_receivable > v_credit_limit then
          raise exception 'Melebihi limit kredit pelanggan (limit %, terpakai %, tagihan %)',
            v_credit_limit, v_outstanding, v_receivable
            using errcode = 'P0001';
        end if;
      end if;

      insert into public.receivables (
        tenant_id, sale_id, customer_id, amount, due_date
      ) values (
        p_tenant_id, v_sale_id, p_customer_id, v_receivable, current_date + 30
      );
    end if;

    -- ─── Audit ───────────────────────────────────────────────────────────────
    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, after, user_id
    ) values (
      p_tenant_id, 'sale', v_sale_id, 'create',
      jsonb_build_object(
        'invoice_no', v_invoice_no,
        'local_invoice_no', p_local_invoice_no,
        'total', v_total,
        'paid_amount', v_paid,
        'status', v_status,
        'needs_review_reason', v_review_reason
      ),
      auth.uid()
    );

    return jsonb_build_object(
      'sale_id', v_sale_id,
      'invoice_no', v_invoice_no,
      'total', v_total,
      'paid_amount', v_paid,
      'change_amount', v_change,
      'status', v_status,
      'needs_review_reason', v_review_reason,
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public._sales_core(
  uuid, uuid, uuid, uuid, jsonb, jsonb, uuid, text, uuid, uuid, boolean, text
) from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- create_sale (ketat, dipakai saat online) — signature tetap sama
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.create_sale(
  p_client_uuid uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_payments jsonb,
  p_shift_id uuid,
  p_note text,
  p_vehicle_id uuid,
  p_work_order_id uuid
) returns jsonb
  language sql
  security definer
  set search_path = public
  as $$
    select public._sales_core(
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false, null
    );
  $$;

revoke execute on function public.create_sale(
  uuid, uuid, uuid, uuid, jsonb, jsonb, uuid, text, uuid, uuid
) from public, anon;
grant execute on function public.create_sale(
  uuid, uuid, uuid, uuid, jsonb, jsonb, uuid, text, uuid, uuid
) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- sync_sale (replay outbox offline)
-- ═══════════════════════════════════════════════════════════════════════════════

create function public.sync_sale(
  p_client_uuid uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_payments jsonb,
  p_shift_id uuid,
  p_note text,
  p_vehicle_id uuid,
  p_work_order_id uuid,
  p_local_invoice_no text
) returns jsonb
  language sql
  security definer
  set search_path = public
  as $$
    select public._sales_core(
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, true, $11
    );
  $$;

revoke execute on function public.sync_sale(
  uuid, uuid, uuid, uuid, jsonb, jsonb, uuid, text, uuid, uuid, text
) from public, anon;
grant execute on function public.sync_sale(
  uuid, uuid, uuid, uuid, jsonb, jsonb, uuid, text, uuid, uuid, text
) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- resolve_sale_review: pemilik menyetujui (potong stok) atau membatalkan
-- ═══════════════════════════════════════════════════════════════════════════════

create function public.resolve_sale_review(
  p_sale_id uuid,
  p_action text,
  p_reason text
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_sale public.sales;
    v_item record;
    v_stock numeric;
    v_status text;
    v_receivable bigint;
    v_outstanding bigint;
    v_credit_limit bigint;
    v_reason text;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk menyelesaikan review'
        using errcode = '28000';
    end if;
    if p_action not in ('accept', 'void') then
      raise exception 'Aksi review tidak dikenal' using errcode = 'P0001';
    end if;

    select * into v_sale
    from public.sales
    where id = p_sale_id
    for update;

    if v_sale.id is null then
      raise exception 'Penjualan tidak ditemukan' using errcode = 'P0001';
    end if;
    if not public.has_role(v_sale.tenant_id, array['owner', 'admin']) then
      raise exception 'Tidak berhak menyelesaikan review' using errcode = '42501';
    end if;

    -- Idempoten: sudah diselesaikan sebelumnya.
    if v_sale.status <> 'needs_review' then
      if (p_action = 'void' and v_sale.status = 'void')
        or (p_action = 'accept' and v_sale.status in ('paid', 'partial', 'credit'))
      then
        return jsonb_build_object(
          'sale_id', v_sale.id,
          'invoice_no', v_sale.invoice_no,
          'status', v_sale.status,
          'idempotent', true
        );
      end if;
      raise exception 'Transaksi tidak dalam status perlu review'
        using errcode = 'P0001';
    end if;

    v_reason := nullif(btrim(coalesce(p_reason, '')), '');
    perform set_config('bengkel.sale_review', 'on', true);

    if p_action = 'void' then
      update public.sales
      set status = 'void',
          void_reason = coalesce(v_reason, 'Dibatalkan saat review'),
          voided_at = now(),
          voided_by = auth.uid(),
          reviewed_at = now(),
          reviewed_by = auth.uid(),
          updated_at = now()
      where id = v_sale.id;

      insert into public.audit_logs (
        tenant_id, entity, entity_id, action, before, after, reason, user_id
      ) values (
        v_sale.tenant_id, 'sale', v_sale.id, 'review_void',
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
    end if;

    -- accept: validasi stok dulu, baru potong (semua atau tidak sama sekali).
    for v_item in
      select si.product_id, si.qty_base, p.track_stock, p.name
      from public.sale_items si
      join public.products p
        on p.tenant_id = si.tenant_id and p.id = si.product_id
      where si.tenant_id = v_sale.tenant_id and si.sale_id = v_sale.id
    loop
      if v_item.track_stock then
        perform pg_advisory_xact_lock(
          hashtextextended(
            v_sale.tenant_id::text || ':' || v_sale.outlet_id::text || ':'
              || v_item.product_id::text,
            0
          )
        );

        select qty_base into v_stock
        from public.stock_levels
        where tenant_id = v_sale.tenant_id
          and product_id = v_item.product_id
          and outlet_id = v_sale.outlet_id
        for update;

        if coalesce(v_stock, 0) < v_item.qty_base then
          raise exception 'Stok % tidak cukup (tersedia %, dibutuhkan %). Sesuaikan stok dulu.',
            v_item.name, coalesce(v_stock, 0), v_item.qty_base
            using errcode = 'P0001';
        end if;
      end if;
    end loop;

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
          -v_item.qty_base, 'sale', 'sale', v_sale.id, v_item.unit_cost,
          'Penjualan ' || v_sale.invoice_no || ' (review disetujui)'
        );
      end if;
    end loop;

    v_status := case
      when v_sale.paid_amount >= v_sale.total then 'paid'
      when v_sale.paid_amount > 0 then 'partial'
      else 'credit'
    end;

    if v_sale.paid_amount < v_sale.total then
      if v_sale.customer_id is null then
        raise exception 'Penjualan kredit wajib punya pelanggan'
          using errcode = 'P0001';
      end if;

      v_receivable := v_sale.total - v_sale.paid_amount;

      select coalesce(credit_limit, 0) into v_credit_limit
      from public.customers
      where tenant_id = v_sale.tenant_id and id = v_sale.customer_id;

      if coalesce(v_credit_limit, 0) > 0 then
        select coalesce(sum(amount), 0) into v_outstanding
        from public.receivables
        where tenant_id = v_sale.tenant_id
          and customer_id = v_sale.customer_id
          and status in ('open', 'partial');

        if v_outstanding + v_receivable > v_credit_limit then
          raise exception 'Melebihi limit kredit pelanggan (limit %, terpakai %, tagihan %)',
            v_credit_limit, v_outstanding, v_receivable
            using errcode = 'P0001';
        end if;
      end if;

      insert into public.receivables (
        tenant_id, sale_id, customer_id, amount, due_date
      ) values (
        v_sale.tenant_id, v_sale.id, v_sale.customer_id, v_receivable,
        current_date + 30
      );
    end if;

    update public.sales
    set status = v_status,
        reviewed_at = now(),
        reviewed_by = auth.uid(),
        updated_at = now()
    where id = v_sale.id;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, before, after, reason, user_id
    ) values (
      v_sale.tenant_id, 'sale', v_sale.id, 'review_accept',
      jsonb_build_object('status', v_sale.status),
      jsonb_build_object('status', v_status),
      coalesce(v_reason, v_sale.needs_review_reason), auth.uid()
    );

    return jsonb_build_object(
      'sale_id', v_sale.id,
      'invoice_no', v_sale.invoice_no,
      'status', v_status,
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public.resolve_sale_review(uuid, text, text)
  from public, anon;
grant execute on function public.resolve_sale_review(uuid, text, text)
  to authenticated;
