-- 0028: _sales_core menghormati harga snapshot work order (T7.3)
-- Saat work order ditagihkan, harga yang dipakai adalah harga yang tercatat di
-- work_order_items (bukan harga jual terkini). Harga tetap divalidasi: nilai yang
-- dikirim hanya diterima bila cocok persis dengan baris item WO yang sama.

create or replace function public._sales_core(
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
    v_price_from_work_order boolean := false;
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
        -- Harga snapshot WO: harga yang sudah tercatat di work_order_items boleh
        -- dipakai walau harga jual produk sudah berubah, asalkan barang, satuan,
        -- qty, dan harganya persis sama dengan baris WO tersebut.
        v_price_from_work_order := false;

        if p_work_order_id is not null then
          select exists (
            select 1
            from public.work_order_items woi
            where woi.tenant_id = p_tenant_id
              and woi.work_order_id = p_work_order_id
              and woi.product_id = v_product.id
              and woi.unit_id = (v_item ->> 'unit_id')::uuid
              and woi.qty = v_qty
              and woi.unit_price = v_unit_price
          ) into v_price_from_work_order;
        end if;

        if v_price_from_work_order then
          -- Harga dari work order: tidak perlu review, transaksi tetap jalan.
          null;
        elsif p_offline then
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

-- _sales_core lama sudah diganti; grant tetap hanya untuk pemanggil internal.
