--
-- PostgreSQL database dump
--


-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: adjust_stock(uuid, uuid, uuid, numeric, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.adjust_stock(p_tenant_id uuid, p_product_id uuid, p_outlet_id uuid, p_qty_base numeric, p_reason text, p_client_uuid uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: apply_stock_movement(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_stock_movement() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  begin
    insert into public.stock_levels (tenant_id, product_id, outlet_id, qty_base)
    values (new.tenant_id, new.product_id, new.outlet_id, new.qty_base)
    on conflict (tenant_id, product_id, outlet_id)
    do update set
      qty_base = public.stock_levels.qty_base + excluded.qty_base,
      updated_at = now();
    return new;
  end;
  $$;


--
-- Name: close_cash_shift(uuid, bigint, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_cash_shift(p_shift_id uuid, p_closing_cash_counted bigint, p_note text, p_client_uuid uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  declare
    v_shift public.cash_shifts;
    v_expected bigint;
    v_difference bigint;
    v_closed_at timestamptz;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk menutup shift' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    select * into v_shift
    from public.cash_shifts
    where id = p_shift_id
    for update;

    if v_shift.id is null then
      raise exception 'Shift tidak ditemukan' using errcode = 'P0001';
    end if;
    if v_shift.cashier_id <> auth.uid()
      and not public.has_role(v_shift.tenant_id, array['owner', 'admin'])
    then
      raise exception 'Tidak berhak menutup shift ini' using errcode = '42501';
    end if;
    if p_closing_cash_counted is null or p_closing_cash_counted < 0 then
      raise exception 'Uang tunai dihitung tidak boleh negatif' using errcode = 'P0001';
    end if;

    if v_shift.closed_at is not null then
      if v_shift.close_client_uuid = p_client_uuid then
        return jsonb_build_object(
          'shift_id', v_shift.id,
          'expected_cash', v_shift.expected_cash,
          'closing_cash_counted', v_shift.closing_cash_counted,
          'difference', v_shift.difference,
          'closed_at', v_shift.closed_at
        );
      end if;
      raise exception 'Shift sudah ditutup' using errcode = 'P0001';
    end if;

    v_expected := public.shift_expected_cash(p_shift_id);
    v_difference := p_closing_cash_counted - v_expected;

    update public.cash_shifts
    set closed_at = now(),
        closing_cash_counted = p_closing_cash_counted,
        expected_cash = v_expected,
        difference = v_difference,
        note = nullif(btrim(coalesce(p_note, '')), ''),
        close_client_uuid = p_client_uuid
    where id = p_shift_id
    returning closed_at into v_closed_at;

    return jsonb_build_object(
      'shift_id', p_shift_id,
      'expected_cash', v_expected,
      'closing_cash_counted', p_closing_cash_counted,
      'difference', v_difference,
      'closed_at', v_closed_at
    );
  end;
  $$;


--
-- Name: create_sale(uuid, uuid, uuid, uuid, jsonb, jsonb, uuid, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_sale(p_client_uuid uuid, p_tenant_id uuid, p_outlet_id uuid, p_customer_id uuid, p_items jsonb, p_payments jsonb, p_shift_id uuid, p_note text, p_vehicle_id uuid, p_work_order_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk membuat penjualan' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    -- Idempotensi: client_uuid sama mengembalikan sale yang sama.
    select id, invoice_no, total, paid_amount, change_amount, status
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
        raise exception 'Harga % tidak sesuai harga jual (seharusnya %)',
          v_product.name, v_expected_price
          using errcode = 'P0001';
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
          raise exception 'Stok % tidak cukup (tersedia %, dibutuhkan %)',
            v_product.name, v_current_stock, v_qty_base
            using errcode = 'P0001';
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

    -- ─── Insert sale ─────────────────────────────────────────────────────────
    v_invoice_no := public.generate_invoice_no(p_tenant_id, p_outlet_id);

    insert into public.sales (
      tenant_id, outlet_id, invoice_no, client_uuid, customer_id, vehicle_id,
      work_order_id, status, subtotal, discount, tax, total, paid_amount,
      change_amount, cashier_id, shift_id, note
    ) values (
      p_tenant_id, p_outlet_id, v_invoice_no, p_client_uuid, p_customer_id,
      p_vehicle_id, p_work_order_id, v_status, v_subtotal, 0, 0, v_total,
      v_paid, v_change, auth.uid(), p_shift_id,
      nullif(btrim(coalesce(p_note, '')), '')
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

      if (v_line ->> 'track_stock')::boolean then
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

    -- ─── Piutang + limit kredit ──────────────────────────────────────────────
    if v_paid < v_total then
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
        'total', v_total,
        'paid_amount', v_paid,
        'status', v_status
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
      'idempotent', false
    );
  end;
  $$;


--
-- Name: create_sale_return(uuid, jsonb, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_sale_return(p_sale_id uuid, p_items jsonb, p_reason text, p_client_uuid uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: create_stock_opname(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_stock_opname(p_tenant_id uuid, p_outlet_id uuid, p_note text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: create_tenant(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_tenant(p_client_uuid uuid, p_name text, p_business_type text, p_outlet_name text) RETURNS TABLE(tenant_id uuid, outlet_id uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  declare
    v_uid uuid := auth.uid();
    v_tenant uuid;
    v_outlet uuid;
    v_owner uuid;
  begin
    if v_uid is null then
      raise exception 'Harus login untuk membuat usaha' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;
    if p_name is null or btrim(p_name) = '' then
      raise exception 'Nama usaha wajib diisi' using errcode = 'P0001';
    end if;
    if p_business_type is null
       or p_business_type not in ('bengkel', 'toko_bangunan', 'both') then
      raise exception 'Tipe usaha tidak valid' using errcode = 'P0001';
    end if;
    if p_outlet_name is null or btrim(p_outlet_name) = '' then
      raise exception 'Nama outlet wajib diisi' using errcode = 'P0001';
    end if;

    -- idempotensi: permintaan yang sama mengembalikan tenant yang sama
    select t.id, t.created_by into v_tenant, v_owner
    from public.tenants t
    where t.client_uuid = p_client_uuid;

    if v_tenant is not null then
      if v_owner is distinct from v_uid then
        raise exception 'client_uuid sudah dipakai' using errcode = 'P0001';
      end if;
      select o.id into v_outlet
      from public.outlets o
      where o.tenant_id = v_tenant
      order by o.created_at, o.id
      limit 1;
      return query select v_tenant, v_outlet;
      return;
    end if;

    insert into public.tenants (name, business_type, client_uuid)
    values (btrim(p_name), p_business_type, p_client_uuid)
    returning id into v_tenant;

    insert into public.outlets (tenant_id, name)
    values (v_tenant, btrim(p_outlet_name))
    returning id into v_outlet;

    insert into public.memberships (tenant_id, user_id, role)
    values (v_tenant, v_uid, 'owner');

    return query select v_tenant, v_outlet;
  end;
  $$;


--
-- Name: generate_invoice_no(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_invoice_no(p_tenant_id uuid, p_outlet_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  declare
    v_seq int;
  begin
    -- Kunci per tenant+outlet supaya dua kasir tidak dapat nomor sama.
    perform pg_advisory_xact_lock(
      hashtextextended(p_tenant_id::text || ':' || p_outlet_id::text, 0)
    );

    select count(*) + 1 into v_seq
    from public.sales
    where tenant_id = p_tenant_id
      and outlet_id = p_outlet_id
      and sold_at::date = current_date;

    return 'INV-' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(v_seq::text, 4, '0');
  end;
  $$;


--
-- Name: has_role(uuid, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_role(t uuid, roles text[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    select exists (
      select 1
      from public.memberships m
      where m.tenant_id = t
        and m.user_id = auth.uid()
        and m.active
        and m.role = any (roles)
    );
  $$;


--
-- Name: is_dev(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_dev() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    select exists (
      select 1
      from public.memberships m
      where m.user_id = auth.uid()
        and m.active
        and m.role = 'dev'
    );
  $$;


--
-- Name: is_member(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_member(t uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    select exists (
      select 1
      from public.memberships m
      where m.tenant_id = t
        and m.user_id = auth.uid()
        and m.active
    );
  $$;


--
-- Name: open_cash_shift(uuid, uuid, bigint, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.open_cash_shift(p_tenant_id uuid, p_outlet_id uuid, p_opening_cash bigint, p_client_uuid uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  declare
    v_id uuid;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk membuka shift' using errcode = '28000';
    end if;
    if not public.has_role(p_tenant_id, array['owner', 'admin', 'kasir']) then
      raise exception 'Tidak berhak membuka shift kasir' using errcode = '42501';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;
    if p_opening_cash is null or p_opening_cash < 0 then
      raise exception 'Modal awal tidak boleh negatif' using errcode = 'P0001';
    end if;
    if not exists (
      select 1 from public.outlets
      where tenant_id = p_tenant_id and id = p_outlet_id
    ) then
      raise exception 'Outlet tidak ditemukan' using errcode = 'P0001';
    end if;

    -- idempotensi
    select id into v_id
    from public.cash_shifts
    where tenant_id = p_tenant_id and client_uuid = p_client_uuid;

    if v_id is not null then
      return v_id;
    end if;

    if exists (
      select 1 from public.cash_shifts
      where tenant_id = p_tenant_id
        and outlet_id = p_outlet_id
        and cashier_id = auth.uid()
        and closed_at is null
    ) then
      raise exception 'Masih ada shift terbuka. Tutup dulu shift sebelumnya.'
        using errcode = 'P0001';
    end if;

    begin
      insert into public.cash_shifts (
        tenant_id, outlet_id, cashier_id, opening_cash, client_uuid
      ) values (
        p_tenant_id, p_outlet_id, auth.uid(), p_opening_cash, p_client_uuid
      )
      returning id into v_id;
    exception when unique_violation then
      -- Balapan dua permintaan: satu menang, yang lain mengembalikan shift yang sama
      -- bila client_uuid sama, atau ditolak bila memang shift lain.
      select id into v_id
      from public.cash_shifts
      where tenant_id = p_tenant_id and client_uuid = p_client_uuid;
      if v_id is null then
        raise exception 'Masih ada shift terbuka. Tutup dulu shift sebelumnya.'
          using errcode = 'P0001';
      end if;
    end;

    return v_id;
  end;
  $$;


--
-- Name: pos_catalog(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pos_catalog(p_tenant_id uuid, p_outlet_id uuid, p_tier_id uuid) RETURNS TABLE(product_id uuid, name text, sku text, barcode text, base_unit_id uuid, base_unit_name text, price bigint, stock_qty numeric, min_stock numeric, is_low boolean, track_stock boolean, units jsonb)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: post_stock_opname(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.post_stock_opname(p_opname_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: prevent_tenant_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_tenant_change() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
  begin
    if new.tenant_id is distinct from old.tenant_id then
      raise exception 'tenant_id tidak boleh diubah (tabel %)', tg_table_name
        using errcode = 'P0001';
    end if;
    return new;
  end;
  $$;


--
-- Name: protect_last_owner(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_last_owner() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  declare
    v_tenant uuid;
    v_other_owner int;
  begin
    if tg_op = 'DELETE' then
      if not (old.role = 'owner' and old.active) then
        return old;
      end if;
      v_tenant := old.tenant_id;
    else
      if not (old.role = 'owner' and old.active
              and (new.role <> 'owner' or new.active = false)) then
        return new;
      end if;
      v_tenant := old.tenant_id;
    end if;

    select count(*) into v_other_owner
    from public.memberships m
    where m.tenant_id = v_tenant
      and m.user_id is distinct from old.user_id
      and m.role = 'owner'
      and m.active;

    if v_other_owner = 0 then
      raise exception 'Owner aktif terakhir tidak boleh dihapus, diturunkan, atau dinonaktifkan (tenant %: hanya % owner aktif tersisa)',
        v_tenant, v_other_owner
        using errcode = 'P0001';
    end if;

    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end;
  $$;


--
-- Name: resolve_price(uuid, uuid, uuid, uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolve_price(p_tenant_id uuid, p_product_id uuid, p_unit_id uuid, p_tier_id uuid, p_qty numeric) RETURNS bigint
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  declare
    v_price bigint;
    v_factor numeric;
    v_base_price bigint;
    v_base_unit uuid;
    v_break bigint;
  begin
    if not public.is_member(p_tenant_id) then
      raise exception 'Tidak berhak membaca harga tenant ini' using errcode = '42501';
    end if;
    if p_qty is null or p_qty <= 0 then
      raise exception 'qty harus lebih dari 0' using errcode = 'P0001';
    end if;

    select base_unit_id, sell_price into v_base_unit, v_base_price
    from public.products
    where tenant_id = p_tenant_id and id = p_product_id;

    if v_base_unit is null then
      raise exception 'Produk tidak ditemukan' using errcode = 'P0001';
    end if;

    -- 1) harga satuan tambahan (jika ada)
    select sell_price, factor_to_base into v_price, v_factor
    from public.product_units
    where tenant_id = p_tenant_id and product_id = p_product_id and unit_id = p_unit_id;

    -- 2) harga base (unit sama dengan base, atau fallback konversi)
    if v_base_unit = p_unit_id then
      v_price := coalesce(v_price, v_base_price);
    elsif v_price is null then
      if v_factor is null then
        raise exception 'Satuan tidak terdaftar untuk produk ini' using errcode = 'P0001';
      end if;
      v_price := round(v_base_price * v_factor);
    end if;

    -- 3) harga tier (menang atas harga satuan)
    if p_tier_id is not null then
      select pp.price into v_price
      from public.product_prices pp
      where pp.tenant_id = p_tenant_id
        and pp.product_id = p_product_id
        and pp.tier_id = p_tier_id
        and pp.unit_id = p_unit_id;

      -- jika tier tidak punya harga untuk unit ini, tetap pakai harga satuan
      if v_price is null then
        select sell_price into v_price
        from public.product_units
        where tenant_id = p_tenant_id and product_id = p_product_id and unit_id = p_unit_id;
        v_price := coalesce(v_price, v_base_price);
      end if;
    end if;

    -- 4) harga grosir: ambil yang terendah di antara break yang berlaku
    select min(price) into v_break
    from public.price_breaks
    where tenant_id = p_tenant_id
      and product_id = p_product_id
      and unit_id = p_unit_id
      and min_qty <= p_qty;

    if v_break is not null then
      v_price := least(v_price, v_break);
    end if;

    return v_price;
  end;
  $$;


--
-- Name: save_stock_opname_counts(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_stock_opname_counts(p_opname_id uuid, p_counts jsonb) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: seed_default_price_tiers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.seed_default_price_tiers() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  begin
    insert into public.price_tiers (tenant_id, name) values
      (new.id, 'Umum'),
      (new.id, 'Langganan'),
      (new.id, 'Kontraktor'),
      (new.id, 'Bengkel Partner')
    on conflict (tenant_id, name) do nothing;
    return new;
  end;
  $$;


--
-- Name: set_created_by(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_created_by() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
  begin
    if tg_op = 'INSERT' then
      if auth.uid() is not null then
        new.created_by = auth.uid();
      end if;
    end if;
    return new;
  end;
  $$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
  begin
    new.updated_at = now();
    return new;
  end;
  $$;


--
-- Name: shift_expected_cash(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.shift_expected_cash(p_shift_id uuid) RETURNS bigint
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  declare
    v_tenant uuid;
    v_opening bigint;
    v_cash_in bigint := 0;
  begin
    select tenant_id, opening_cash into v_tenant, v_opening
    from public.cash_shifts
    where id = p_shift_id;

    if v_tenant is null then
      raise exception 'Shift tidak ditemukan' using errcode = 'P0001';
    end if;
    if not public.is_member(v_tenant) then
      raise exception 'Tidak berhak membaca shift ini' using errcode = '42501';
    end if;

    select coalesce(sum(g.cash), 0) into v_cash_in
    from (
      select greatest(
        coalesce(sum(p.amount) filter (where p.method = 'tunai'), 0)
          - s.change_amount,
        0
      ) as cash
      from public.sales s
      left join public.payments p
        on p.tenant_id = s.tenant_id and p.sale_id = s.id
      where s.tenant_id = v_tenant
        and s.shift_id = p_shift_id
        and s.status <> 'void'
      group by s.id, s.change_amount
    ) g;

    return v_opening + v_cash_in;
  end;
  $$;


--
-- Name: stock_movements_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stock_movements_append_only() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
  begin
    raise exception 'stock_movements bersifat append-only (koreksi lewat movement balik)'
      using errcode = 'P0001';
  end;
  $$;


--
-- Name: void_sale(uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.void_sale(p_sale_id uuid, p_reason text, p_client_uuid uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    entity text NOT NULL,
    entity_id uuid NOT NULL,
    action text NOT NULL,
    before jsonb,
    after jsonb,
    reason text,
    user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cash_shifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_shifts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    outlet_id uuid NOT NULL,
    cashier_id uuid NOT NULL,
    opening_cash bigint NOT NULL,
    opened_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone,
    closing_cash_counted bigint,
    expected_cash bigint,
    difference bigint,
    note text,
    client_uuid uuid NOT NULL,
    close_client_uuid uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT cash_shifts_closed_fields CHECK ((((closed_at IS NULL) AND (closing_cash_counted IS NULL) AND (expected_cash IS NULL) AND (difference IS NULL)) OR ((closed_at IS NOT NULL) AND (closing_cash_counted IS NOT NULL) AND (expected_cash IS NOT NULL) AND (difference IS NOT NULL)))),
    CONSTRAINT cash_shifts_closing_cash_counted_check CHECK ((closing_cash_counted >= 0)),
    CONSTRAINT cash_shifts_expected_cash_check CHECK ((expected_cash >= 0)),
    CONSTRAINT cash_shifts_opening_cash_check CHECK ((opening_cash >= 0))
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    parent_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT categories_name_check CHECK ((btrim(name) <> ''::text))
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    phone text,
    address text,
    tier_id uuid,
    credit_limit bigint DEFAULT 0 NOT NULL,
    notes text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT customers_credit_limit_check CHECK ((credit_limit >= 0)),
    CONSTRAINT customers_name_check CHECK ((btrim(name) <> ''::text))
);


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text DEFAULT 'kasir'::text NOT NULL,
    outlet_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT memberships_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'kasir'::text, 'mekanik'::text, 'gudang'::text, 'dev'::text])))
);


--
-- Name: outlets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outlets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    address text,
    phone text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    sale_id uuid NOT NULL,
    method text NOT NULL,
    amount bigint NOT NULL,
    reference text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payments_amount_check CHECK ((amount > 0)),
    CONSTRAINT payments_method_check CHECK ((method = ANY (ARRAY['tunai'::text, 'transfer'::text, 'qris'::text, 'debit'::text, 'kredit_tempo'::text])))
);


--
-- Name: price_breaks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_breaks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    min_qty numeric NOT NULL,
    price bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT price_breaks_min_qty_check CHECK ((min_qty > (0)::numeric)),
    CONSTRAINT price_breaks_price_check CHECK ((price >= 0))
);


--
-- Name: price_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_tiers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT price_tiers_name_check CHECK ((btrim(name) <> ''::text))
);


--
-- Name: product_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_prices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    tier_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    price bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT product_prices_price_check CHECK ((price >= 0))
);


--
-- Name: product_units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_units (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    factor_to_base numeric NOT NULL,
    sell_price bigint DEFAULT 0 NOT NULL,
    barcode text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT product_units_factor_to_base_check CHECK ((factor_to_base > (0)::numeric)),
    CONSTRAINT product_units_sell_price_check CHECK ((sell_price >= 0))
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    sku text,
    barcode text,
    name text NOT NULL,
    category_id uuid,
    kind text DEFAULT 'barang'::text NOT NULL,
    base_unit_id uuid,
    track_stock boolean DEFAULT true NOT NULL,
    cost_price bigint DEFAULT 0 NOT NULL,
    sell_price bigint DEFAULT 0 NOT NULL,
    min_stock numeric DEFAULT 0 NOT NULL,
    image_url text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT products_cost_price_check CHECK ((cost_price >= 0)),
    CONSTRAINT products_kind_check CHECK ((kind = ANY (ARRAY['barang'::text, 'jasa'::text, 'paket'::text]))),
    CONSTRAINT products_min_stock_check CHECK ((min_stock >= (0)::numeric)),
    CONSTRAINT products_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT products_sell_price_check CHECK ((sell_price >= 0))
);


--
-- Name: receivables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receivables (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    sale_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    amount bigint NOT NULL,
    due_date date NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT receivables_amount_check CHECK ((amount > 0)),
    CONSTRAINT receivables_status_check CHECK ((status = ANY (ARRAY['open'::text, 'partial'::text, 'paid'::text])))
);


--
-- Name: sale_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sale_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    sale_id uuid NOT NULL,
    product_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    qty numeric NOT NULL,
    qty_base numeric NOT NULL,
    unit_price bigint NOT NULL,
    unit_cost bigint DEFAULT 0 NOT NULL,
    discount bigint DEFAULT 0 NOT NULL,
    line_total bigint NOT NULL,
    note text,
    mechanic_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sale_items_discount_check CHECK ((discount >= 0)),
    CONSTRAINT sale_items_line_total_check CHECK ((line_total >= 0)),
    CONSTRAINT sale_items_qty_base_check CHECK ((qty_base > (0)::numeric)),
    CONSTRAINT sale_items_qty_check CHECK ((qty > (0)::numeric)),
    CONSTRAINT sale_items_unit_cost_check CHECK ((unit_cost >= 0)),
    CONSTRAINT sale_items_unit_price_check CHECK ((unit_price >= 0))
);


--
-- Name: sale_return_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sale_return_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    return_id uuid NOT NULL,
    sale_item_id uuid NOT NULL,
    product_id uuid NOT NULL,
    qty numeric NOT NULL,
    qty_base numeric NOT NULL,
    unit_price bigint NOT NULL,
    line_total bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sale_return_items_line_total_check CHECK ((line_total >= 0)),
    CONSTRAINT sale_return_items_qty_base_check CHECK ((qty_base > (0)::numeric)),
    CONSTRAINT sale_return_items_qty_check CHECK ((qty > (0)::numeric)),
    CONSTRAINT sale_return_items_unit_price_check CHECK ((unit_price >= 0))
);


--
-- Name: sale_returns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sale_returns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    sale_id uuid NOT NULL,
    reason text NOT NULL,
    client_uuid uuid NOT NULL,
    total bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT sale_returns_reason_check CHECK ((btrim(reason) <> ''::text)),
    CONSTRAINT sale_returns_total_check CHECK ((total >= 0))
);


--
-- Name: sales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    outlet_id uuid NOT NULL,
    invoice_no text NOT NULL,
    client_uuid uuid NOT NULL,
    customer_id uuid,
    vehicle_id uuid,
    work_order_id uuid,
    status text NOT NULL,
    subtotal bigint NOT NULL,
    discount bigint DEFAULT 0 NOT NULL,
    tax bigint DEFAULT 0 NOT NULL,
    total bigint NOT NULL,
    paid_amount bigint NOT NULL,
    change_amount bigint DEFAULT 0 NOT NULL,
    cashier_id uuid NOT NULL,
    shift_id uuid,
    sold_at timestamp with time zone DEFAULT now() NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    void_reason text,
    voided_at timestamp with time zone,
    voided_by uuid,
    void_client_uuid uuid,
    CONSTRAINT sales_change_amount_check CHECK ((change_amount >= 0)),
    CONSTRAINT sales_discount_check CHECK ((discount >= 0)),
    CONSTRAINT sales_paid_amount_check CHECK ((paid_amount >= 0)),
    CONSTRAINT sales_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'paid'::text, 'partial'::text, 'credit'::text, 'void'::text]))),
    CONSTRAINT sales_subtotal_check CHECK ((subtotal >= 0)),
    CONSTRAINT sales_tax_check CHECK ((tax >= 0)),
    CONSTRAINT sales_total_check CHECK ((total >= 0))
);


--
-- Name: stock_levels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_levels (
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    outlet_id uuid NOT NULL,
    qty_base numeric DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: stock_by_outlet; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.stock_by_outlet WITH (security_invoker='true') AS
 SELECT sl.tenant_id,
    sl.outlet_id,
    o.name AS outlet_name,
    sl.product_id,
    p.name AS product_name,
    p.sku,
    sl.qty_base,
    p.min_stock,
    (p.track_stock AND (p.min_stock > (0)::numeric) AND (sl.qty_base < p.min_stock)) AS is_low
   FROM ((public.stock_levels sl
     JOIN public.outlets o ON (((o.tenant_id = sl.tenant_id) AND (o.id = sl.outlet_id))))
     JOIN public.products p ON (((p.tenant_id = sl.tenant_id) AND (p.id = sl.product_id))));


--
-- Name: stock_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_movements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    outlet_id uuid NOT NULL,
    qty_base numeric NOT NULL,
    type text NOT NULL,
    ref_type text,
    ref_id uuid,
    unit_cost bigint DEFAULT 0 NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    client_uuid uuid,
    CONSTRAINT stock_movements_qty_base_check CHECK ((qty_base <> (0)::numeric)),
    CONSTRAINT stock_movements_type_check CHECK ((type = ANY (ARRAY['purchase'::text, 'sale'::text, 'sale_return'::text, 'adjustment'::text, 'opname'::text, 'transfer_in'::text, 'transfer_out'::text, 'workorder_use'::text]))),
    CONSTRAINT stock_movements_unit_cost_check CHECK ((unit_cost >= 0))
);


--
-- Name: stock_opname_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_opname_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    opname_id uuid NOT NULL,
    product_id uuid NOT NULL,
    system_qty numeric DEFAULT 0 NOT NULL,
    counted_qty numeric,
    difference numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: stock_opnames; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_opnames (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    outlet_id uuid NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    posted_at timestamp with time zone,
    posted_by uuid,
    CONSTRAINT stock_opnames_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'posted'::text, 'cancelled'::text])))
);


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    phone text,
    address text,
    payment_terms_days integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT suppliers_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT suppliers_payment_terms_days_check CHECK ((payment_terms_days >= 0))
);


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    business_type text DEFAULT 'both'::text NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    client_uuid uuid,
    CONSTRAINT tenants_business_type_check CHECK ((business_type = ANY (ARRAY['bengkel'::text, 'toko_bangunan'::text, 'both'::text])))
);


--
-- Name: units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.units (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT units_name_check CHECK ((btrim(name) <> ''::text))
);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: cash_shifts cash_shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_shifts
    ADD CONSTRAINT cash_shifts_pkey PRIMARY KEY (id);


--
-- Name: cash_shifts cash_shifts_tenant_id_client_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_shifts
    ADD CONSTRAINT cash_shifts_tenant_id_client_uuid_key UNIQUE (tenant_id, client_uuid);


--
-- Name: cash_shifts cash_shifts_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_shifts
    ADD CONSTRAINT cash_shifts_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: categories categories_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: customers customers_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_tenant_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_tenant_id_user_id_key UNIQUE (tenant_id, user_id);


--
-- Name: outlets outlets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outlets
    ADD CONSTRAINT outlets_pkey PRIMARY KEY (id);


--
-- Name: outlets outlets_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outlets
    ADD CONSTRAINT outlets_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: payments payments_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: price_breaks price_breaks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_breaks
    ADD CONSTRAINT price_breaks_pkey PRIMARY KEY (id);


--
-- Name: price_breaks price_breaks_tenant_id_product_id_unit_id_min_qty_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_breaks
    ADD CONSTRAINT price_breaks_tenant_id_product_id_unit_id_min_qty_key UNIQUE (tenant_id, product_id, unit_id, min_qty);


--
-- Name: price_tiers price_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_tiers
    ADD CONSTRAINT price_tiers_pkey PRIMARY KEY (id);


--
-- Name: price_tiers price_tiers_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_tiers
    ADD CONSTRAINT price_tiers_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: price_tiers price_tiers_tenant_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_tiers
    ADD CONSTRAINT price_tiers_tenant_id_name_key UNIQUE (tenant_id, name);


--
-- Name: product_prices product_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_prices
    ADD CONSTRAINT product_prices_pkey PRIMARY KEY (id);


--
-- Name: product_prices product_prices_tenant_id_product_id_tier_id_unit_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_prices
    ADD CONSTRAINT product_prices_tenant_id_product_id_tier_id_unit_id_key UNIQUE (tenant_id, product_id, tier_id, unit_id);


--
-- Name: product_units product_units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT product_units_pkey PRIMARY KEY (id);


--
-- Name: product_units product_units_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT product_units_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: product_units product_units_tenant_id_product_id_unit_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT product_units_tenant_id_product_id_unit_id_key UNIQUE (tenant_id, product_id, unit_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: products products_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: receivables receivables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT receivables_pkey PRIMARY KEY (id);


--
-- Name: receivables receivables_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT receivables_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: receivables receivables_tenant_id_sale_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT receivables_tenant_id_sale_id_key UNIQUE (tenant_id, sale_id);


--
-- Name: sale_items sale_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_pkey PRIMARY KEY (id);


--
-- Name: sale_items sale_items_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: sale_return_items sale_return_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_items
    ADD CONSTRAINT sale_return_items_pkey PRIMARY KEY (id);


--
-- Name: sale_return_items sale_return_items_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_items
    ADD CONSTRAINT sale_return_items_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: sale_returns sale_returns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT sale_returns_pkey PRIMARY KEY (id);


--
-- Name: sale_returns sale_returns_tenant_id_client_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT sale_returns_tenant_id_client_uuid_key UNIQUE (tenant_id, client_uuid);


--
-- Name: sale_returns sale_returns_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT sale_returns_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: sales sales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_pkey PRIMARY KEY (id);


--
-- Name: sales sales_tenant_id_client_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_tenant_id_client_uuid_key UNIQUE (tenant_id, client_uuid);


--
-- Name: sales sales_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: sales sales_tenant_id_outlet_id_invoice_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_tenant_id_outlet_id_invoice_no_key UNIQUE (tenant_id, outlet_id, invoice_no);


--
-- Name: stock_levels stock_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_pkey PRIMARY KEY (tenant_id, product_id, outlet_id);


--
-- Name: stock_movements stock_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_pkey PRIMARY KEY (id);


--
-- Name: stock_opname_items stock_opname_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_opname_items
    ADD CONSTRAINT stock_opname_items_pkey PRIMARY KEY (id);


--
-- Name: stock_opname_items stock_opname_items_tenant_id_opname_id_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_opname_items
    ADD CONSTRAINT stock_opname_items_tenant_id_opname_id_product_id_key UNIQUE (tenant_id, opname_id, product_id);


--
-- Name: stock_opnames stock_opnames_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_opnames
    ADD CONSTRAINT stock_opnames_pkey PRIMARY KEY (id);


--
-- Name: stock_opnames stock_opnames_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_opnames
    ADD CONSTRAINT stock_opnames_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: suppliers suppliers_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: tenants tenants_client_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_client_uuid_key UNIQUE (client_uuid);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (id);


--
-- Name: units units_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: units units_tenant_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_tenant_id_name_key UNIQUE (tenant_id, name);


--
-- Name: audit_logs_entity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_entity_idx ON public.audit_logs USING btree (tenant_id, entity, created_at DESC);


--
-- Name: cash_shifts_cashier_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cash_shifts_cashier_idx ON public.cash_shifts USING btree (tenant_id, cashier_id, opened_at DESC);


--
-- Name: cash_shifts_one_open_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cash_shifts_one_open_key ON public.cash_shifts USING btree (tenant_id, outlet_id, cashier_id) WHERE (closed_at IS NULL);


--
-- Name: cash_shifts_tenant_opened_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cash_shifts_tenant_opened_idx ON public.cash_shifts USING btree (tenant_id, opened_at DESC);


--
-- Name: categories_parent_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX categories_parent_idx ON public.categories USING btree (tenant_id, parent_id);


--
-- Name: customers_tenant_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customers_tenant_name_idx ON public.customers USING btree (tenant_id, name);


--
-- Name: customers_tenant_phone_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customers_tenant_phone_idx ON public.customers USING btree (tenant_id, phone);


--
-- Name: idx_memberships_tenant_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_tenant_user ON public.memberships USING btree (tenant_id, user_id);


--
-- Name: idx_memberships_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_user ON public.memberships USING btree (user_id) WHERE active;


--
-- Name: idx_outlets_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outlets_tenant ON public.outlets USING btree (tenant_id);


--
-- Name: payments_sale_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_sale_idx ON public.payments USING btree (tenant_id, sale_id);


--
-- Name: price_breaks_product_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX price_breaks_product_idx ON public.price_breaks USING btree (tenant_id, product_id);


--
-- Name: price_tiers_tenant_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX price_tiers_tenant_idx ON public.price_tiers USING btree (tenant_id, name);


--
-- Name: product_prices_product_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_prices_product_idx ON public.product_prices USING btree (tenant_id, product_id);


--
-- Name: product_units_product_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX product_units_product_idx ON public.product_units USING btree (tenant_id, product_id);


--
-- Name: products_tenant_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_tenant_active_idx ON public.products USING btree (tenant_id, active);


--
-- Name: products_tenant_barcode_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX products_tenant_barcode_key ON public.products USING btree (tenant_id, barcode) WHERE ((barcode IS NOT NULL) AND (btrim(barcode) <> ''::text));


--
-- Name: products_tenant_category_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_tenant_category_idx ON public.products USING btree (tenant_id, category_id);


--
-- Name: products_tenant_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX products_tenant_name_idx ON public.products USING btree (tenant_id, name);


--
-- Name: products_tenant_sku_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX products_tenant_sku_key ON public.products USING btree (tenant_id, sku) WHERE ((sku IS NOT NULL) AND (btrim(sku) <> ''::text));


--
-- Name: receivables_customer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX receivables_customer_idx ON public.receivables USING btree (tenant_id, customer_id, due_date);


--
-- Name: receivables_due_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX receivables_due_date_idx ON public.receivables USING btree (tenant_id, due_date, status);


--
-- Name: sale_items_product_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sale_items_product_idx ON public.sale_items USING btree (tenant_id, product_id);


--
-- Name: sale_items_sale_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sale_items_sale_idx ON public.sale_items USING btree (tenant_id, sale_id);


--
-- Name: sale_return_items_return_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sale_return_items_return_idx ON public.sale_return_items USING btree (tenant_id, return_id);


--
-- Name: sale_return_items_sale_item_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sale_return_items_sale_item_idx ON public.sale_return_items USING btree (tenant_id, sale_item_id);


--
-- Name: sale_returns_sale_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sale_returns_sale_idx ON public.sale_returns USING btree (tenant_id, sale_id, created_at DESC);


--
-- Name: sales_customer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_customer_idx ON public.sales USING btree (tenant_id, customer_id, sold_at DESC);


--
-- Name: sales_shift_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_shift_idx ON public.sales USING btree (tenant_id, shift_id);


--
-- Name: sales_tenant_outlet_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_tenant_outlet_idx ON public.sales USING btree (tenant_id, outlet_id, sold_at DESC);


--
-- Name: sales_tenant_sold_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_tenant_sold_idx ON public.sales USING btree (tenant_id, sold_at DESC);


--
-- Name: sales_void_client_uuid_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_void_client_uuid_key ON public.sales USING btree (tenant_id, void_client_uuid) WHERE (void_client_uuid IS NOT NULL);


--
-- Name: stock_movements_product_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_movements_product_idx ON public.stock_movements USING btree (tenant_id, product_id, outlet_id, created_at);


--
-- Name: stock_movements_tenant_client_uuid_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX stock_movements_tenant_client_uuid_key ON public.stock_movements USING btree (tenant_id, client_uuid) WHERE (client_uuid IS NOT NULL);


--
-- Name: stock_movements_tenant_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_movements_tenant_date_idx ON public.stock_movements USING btree (tenant_id, created_at);


--
-- Name: stock_opname_items_opname_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_opname_items_opname_idx ON public.stock_opname_items USING btree (tenant_id, opname_id);


--
-- Name: stock_opnames_tenant_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_opnames_tenant_idx ON public.stock_opnames USING btree (tenant_id, created_at DESC);


--
-- Name: suppliers_tenant_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX suppliers_tenant_name_idx ON public.suppliers USING btree (tenant_id, name);


--
-- Name: cash_shifts cash_shifts_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cash_shifts_created_by BEFORE INSERT ON public.cash_shifts FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: cash_shifts cash_shifts_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cash_shifts_tenant_id_immutable BEFORE UPDATE ON public.cash_shifts FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: cash_shifts cash_shifts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cash_shifts_updated_at BEFORE UPDATE ON public.cash_shifts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: categories categories_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER categories_created_by BEFORE INSERT ON public.categories FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: categories categories_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER categories_tenant_id_immutable BEFORE UPDATE ON public.categories FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: categories categories_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER categories_updated_at BEFORE UPDATE ON public.categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: customers customers_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER customers_created_by BEFORE INSERT ON public.customers FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: customers customers_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER customers_tenant_id_immutable BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: customers customers_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER customers_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: memberships memberships_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER memberships_created_by BEFORE INSERT ON public.memberships FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: memberships memberships_protect_last_owner; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER memberships_protect_last_owner BEFORE DELETE OR UPDATE ON public.memberships FOR EACH ROW EXECUTE FUNCTION public.protect_last_owner();


--
-- Name: memberships memberships_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER memberships_tenant_id_immutable BEFORE UPDATE ON public.memberships FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: memberships memberships_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER memberships_updated_at BEFORE UPDATE ON public.memberships FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: outlets outlets_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER outlets_created_by BEFORE INSERT ON public.outlets FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: outlets outlets_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER outlets_tenant_id_immutable BEFORE UPDATE ON public.outlets FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: outlets outlets_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER outlets_updated_at BEFORE UPDATE ON public.outlets FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: price_breaks price_breaks_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER price_breaks_created_by BEFORE INSERT ON public.price_breaks FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: price_breaks price_breaks_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER price_breaks_tenant_id_immutable BEFORE UPDATE ON public.price_breaks FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: price_breaks price_breaks_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER price_breaks_updated_at BEFORE UPDATE ON public.price_breaks FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: price_tiers price_tiers_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER price_tiers_created_by BEFORE INSERT ON public.price_tiers FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: price_tiers price_tiers_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER price_tiers_tenant_id_immutable BEFORE UPDATE ON public.price_tiers FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: price_tiers price_tiers_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER price_tiers_updated_at BEFORE UPDATE ON public.price_tiers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: product_prices product_prices_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_prices_created_by BEFORE INSERT ON public.product_prices FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: product_prices product_prices_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_prices_tenant_id_immutable BEFORE UPDATE ON public.product_prices FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: product_prices product_prices_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_prices_updated_at BEFORE UPDATE ON public.product_prices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: product_units product_units_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_units_created_by BEFORE INSERT ON public.product_units FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: product_units product_units_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_units_tenant_id_immutable BEFORE UPDATE ON public.product_units FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: product_units product_units_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER product_units_updated_at BEFORE UPDATE ON public.product_units FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: products products_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER products_created_by BEFORE INSERT ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: products products_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER products_tenant_id_immutable BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: products products_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: receivables receivables_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER receivables_created_by BEFORE INSERT ON public.receivables FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: receivables receivables_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER receivables_tenant_id_immutable BEFORE UPDATE ON public.receivables FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: receivables receivables_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER receivables_updated_at BEFORE UPDATE ON public.receivables FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: sale_returns sale_returns_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sale_returns_created_by BEFORE INSERT ON public.sale_returns FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: sale_returns sale_returns_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sale_returns_tenant_id_immutable BEFORE UPDATE ON public.sale_returns FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: sales sales_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sales_created_by BEFORE INSERT ON public.sales FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: sales sales_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sales_tenant_id_immutable BEFORE UPDATE ON public.sales FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: sales sales_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sales_updated_at BEFORE UPDATE ON public.sales FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: stock_movements stock_movements_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stock_movements_append_only BEFORE DELETE OR UPDATE ON public.stock_movements FOR EACH ROW EXECUTE FUNCTION public.stock_movements_append_only();


--
-- Name: stock_movements stock_movements_apply; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stock_movements_apply AFTER INSERT ON public.stock_movements FOR EACH ROW EXECUTE FUNCTION public.apply_stock_movement();


--
-- Name: stock_movements stock_movements_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stock_movements_created_by BEFORE INSERT ON public.stock_movements FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: stock_opnames stock_opnames_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stock_opnames_created_by BEFORE INSERT ON public.stock_opnames FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: stock_opnames stock_opnames_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stock_opnames_tenant_id_immutable BEFORE UPDATE ON public.stock_opnames FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: stock_opnames stock_opnames_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stock_opnames_updated_at BEFORE UPDATE ON public.stock_opnames FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: suppliers suppliers_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER suppliers_created_by BEFORE INSERT ON public.suppliers FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: suppliers suppliers_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER suppliers_tenant_id_immutable BEFORE UPDATE ON public.suppliers FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: suppliers suppliers_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER suppliers_updated_at BEFORE UPDATE ON public.suppliers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: tenants tenants_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tenants_created_by BEFORE INSERT ON public.tenants FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: tenants tenants_default_price_tiers; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tenants_default_price_tiers AFTER INSERT ON public.tenants FOR EACH ROW EXECUTE FUNCTION public.seed_default_price_tiers();


--
-- Name: tenants tenants_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tenants_updated_at BEFORE UPDATE ON public.tenants FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: units units_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER units_created_by BEFORE INSERT ON public.units FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: units units_tenant_id_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER units_tenant_id_immutable BEFORE UPDATE ON public.units FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_change();


--
-- Name: units units_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER units_updated_at BEFORE UPDATE ON public.units FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: audit_logs audit_logs_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: cash_shifts cash_shifts_outlet_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_shifts
    ADD CONSTRAINT cash_shifts_outlet_same_tenant FOREIGN KEY (tenant_id, outlet_id) REFERENCES public.outlets(tenant_id, id);


--
-- Name: cash_shifts cash_shifts_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_shifts
    ADD CONSTRAINT cash_shifts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: categories categories_parent_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_same_tenant FOREIGN KEY (tenant_id, parent_id) REFERENCES public.categories(tenant_id, id);


--
-- Name: categories categories_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: customers customers_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: customers customers_tier_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_tier_same_tenant FOREIGN KEY (tenant_id, tier_id) REFERENCES public.price_tiers(tenant_id, id);


--
-- Name: memberships memberships_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: memberships memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: outlets outlets_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outlets
    ADD CONSTRAINT outlets_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: payments payments_sale_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_sale_same_tenant FOREIGN KEY (tenant_id, sale_id) REFERENCES public.sales(tenant_id, id) ON DELETE CASCADE;


--
-- Name: payments payments_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: price_breaks price_breaks_product_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_breaks
    ADD CONSTRAINT price_breaks_product_same_tenant FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id) ON DELETE CASCADE;


--
-- Name: price_breaks price_breaks_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_breaks
    ADD CONSTRAINT price_breaks_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: price_breaks price_breaks_unit_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_breaks
    ADD CONSTRAINT price_breaks_unit_same_tenant FOREIGN KEY (tenant_id, unit_id) REFERENCES public.units(tenant_id, id);


--
-- Name: price_tiers price_tiers_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_tiers
    ADD CONSTRAINT price_tiers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: product_prices product_prices_product_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_prices
    ADD CONSTRAINT product_prices_product_same_tenant FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id) ON DELETE CASCADE;


--
-- Name: product_prices product_prices_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_prices
    ADD CONSTRAINT product_prices_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: product_prices product_prices_tier_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_prices
    ADD CONSTRAINT product_prices_tier_same_tenant FOREIGN KEY (tenant_id, tier_id) REFERENCES public.price_tiers(tenant_id, id) ON DELETE CASCADE;


--
-- Name: product_prices product_prices_unit_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_prices
    ADD CONSTRAINT product_prices_unit_same_tenant FOREIGN KEY (tenant_id, unit_id) REFERENCES public.units(tenant_id, id);


--
-- Name: product_units product_units_product_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT product_units_product_same_tenant FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id) ON DELETE CASCADE;


--
-- Name: product_units product_units_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT product_units_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: product_units product_units_unit_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_units
    ADD CONSTRAINT product_units_unit_same_tenant FOREIGN KEY (tenant_id, unit_id) REFERENCES public.units(tenant_id, id);


--
-- Name: products products_category_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_same_tenant FOREIGN KEY (tenant_id, category_id) REFERENCES public.categories(tenant_id, id);


--
-- Name: products products_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: products products_unit_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_unit_same_tenant FOREIGN KEY (tenant_id, base_unit_id) REFERENCES public.units(tenant_id, id);


--
-- Name: receivables receivables_customer_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT receivables_customer_same_tenant FOREIGN KEY (tenant_id, customer_id) REFERENCES public.customers(tenant_id, id);


--
-- Name: receivables receivables_sale_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT receivables_sale_same_tenant FOREIGN KEY (tenant_id, sale_id) REFERENCES public.sales(tenant_id, id);


--
-- Name: receivables receivables_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT receivables_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: sale_items sale_items_product_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_product_same_tenant FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id);


--
-- Name: sale_items sale_items_sale_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_sale_same_tenant FOREIGN KEY (tenant_id, sale_id) REFERENCES public.sales(tenant_id, id) ON DELETE CASCADE;


--
-- Name: sale_items sale_items_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: sale_items sale_items_unit_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_unit_same_tenant FOREIGN KEY (tenant_id, unit_id) REFERENCES public.units(tenant_id, id);


--
-- Name: sale_return_items sale_return_items_product_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_items
    ADD CONSTRAINT sale_return_items_product_same_tenant FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id);


--
-- Name: sale_return_items sale_return_items_return_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_items
    ADD CONSTRAINT sale_return_items_return_same_tenant FOREIGN KEY (tenant_id, return_id) REFERENCES public.sale_returns(tenant_id, id) ON DELETE CASCADE;


--
-- Name: sale_return_items sale_return_items_sale_item_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_items
    ADD CONSTRAINT sale_return_items_sale_item_same_tenant FOREIGN KEY (tenant_id, sale_item_id) REFERENCES public.sale_items(tenant_id, id);


--
-- Name: sale_return_items sale_return_items_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_return_items
    ADD CONSTRAINT sale_return_items_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: sale_returns sale_returns_sale_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT sale_returns_sale_same_tenant FOREIGN KEY (tenant_id, sale_id) REFERENCES public.sales(tenant_id, id);


--
-- Name: sale_returns sale_returns_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_returns
    ADD CONSTRAINT sale_returns_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: sales sales_customer_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_customer_same_tenant FOREIGN KEY (tenant_id, customer_id) REFERENCES public.customers(tenant_id, id);


--
-- Name: sales sales_outlet_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_outlet_same_tenant FOREIGN KEY (tenant_id, outlet_id) REFERENCES public.outlets(tenant_id, id);


--
-- Name: sales sales_shift_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_shift_same_tenant FOREIGN KEY (tenant_id, shift_id) REFERENCES public.cash_shifts(tenant_id, id);


--
-- Name: sales sales_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: stock_levels stock_levels_outlet_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_outlet_same_tenant FOREIGN KEY (tenant_id, outlet_id) REFERENCES public.outlets(tenant_id, id) ON DELETE CASCADE;


--
-- Name: stock_levels stock_levels_product_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_product_same_tenant FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id) ON DELETE CASCADE;


--
-- Name: stock_levels stock_levels_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: stock_movements stock_movements_outlet_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_outlet_same_tenant FOREIGN KEY (tenant_id, outlet_id) REFERENCES public.outlets(tenant_id, id);


--
-- Name: stock_movements stock_movements_product_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_product_same_tenant FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id);


--
-- Name: stock_movements stock_movements_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: stock_opname_items stock_opname_items_opname_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_opname_items
    ADD CONSTRAINT stock_opname_items_opname_same_tenant FOREIGN KEY (tenant_id, opname_id) REFERENCES public.stock_opnames(tenant_id, id) ON DELETE CASCADE;


--
-- Name: stock_opname_items stock_opname_items_product_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_opname_items
    ADD CONSTRAINT stock_opname_items_product_same_tenant FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id);


--
-- Name: stock_opname_items stock_opname_items_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_opname_items
    ADD CONSTRAINT stock_opname_items_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: stock_opnames stock_opnames_outlet_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_opnames
    ADD CONSTRAINT stock_opnames_outlet_same_tenant FOREIGN KEY (tenant_id, outlet_id) REFERENCES public.outlets(tenant_id, id);


--
-- Name: stock_opnames stock_opnames_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_opnames
    ADD CONSTRAINT stock_opnames_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: suppliers suppliers_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: units units_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs audit_logs_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_logs_select_member ON public.audit_logs FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: cash_shifts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cash_shifts ENABLE ROW LEVEL SECURITY;

--
-- Name: cash_shifts cash_shifts_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cash_shifts_select_member ON public.cash_shifts FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: categories categories_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_delete_admin ON public.categories FOR DELETE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: categories categories_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_insert_admin ON public.categories FOR INSERT TO authenticated WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: categories categories_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_select_member ON public.categories FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: categories categories_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_update_admin ON public.categories FOR UPDATE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text])) WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: customers customers_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_delete_admin ON public.customers FOR DELETE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: customers customers_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_insert_admin ON public.customers FOR INSERT TO authenticated WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: customers customers_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_select_member ON public.customers FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: customers customers_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_update_admin ON public.customers FOR UPDATE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text])) WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: memberships memberships_delete_admin_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_delete_admin_or_dev ON public.memberships FOR DELETE TO authenticated USING (((public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev()) AND (auth.uid() IS DISTINCT FROM user_id) AND ((role <> 'owner'::text) OR public.has_role(tenant_id, ARRAY['owner'::text]) OR public.is_dev()) AND ((role <> 'dev'::text) OR public.is_dev())));


--
-- Name: memberships memberships_insert_admin_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_insert_admin_or_dev ON public.memberships FOR INSERT TO authenticated WITH CHECK (((public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev()) AND ((role <> 'owner'::text) OR public.has_role(tenant_id, ARRAY['owner'::text]) OR public.is_dev()) AND ((role <> 'dev'::text) OR public.is_dev()) AND (auth.uid() IS DISTINCT FROM user_id)));


--
-- Name: memberships memberships_select_member_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_select_member_or_dev ON public.memberships FOR SELECT TO authenticated USING ((public.is_member(tenant_id) OR public.is_dev()));


--
-- Name: memberships memberships_update_admin_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_update_admin_or_dev ON public.memberships FOR UPDATE TO authenticated USING (((public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev()) AND (auth.uid() IS DISTINCT FROM user_id) AND ((role <> 'owner'::text) OR public.has_role(tenant_id, ARRAY['owner'::text]) OR public.is_dev()) AND ((role <> 'dev'::text) OR public.is_dev()))) WITH CHECK (((public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev()) AND (auth.uid() IS DISTINCT FROM user_id) AND ((role <> 'owner'::text) OR public.has_role(tenant_id, ARRAY['owner'::text]) OR public.is_dev()) AND ((role <> 'dev'::text) OR public.is_dev())));


--
-- Name: outlets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.outlets ENABLE ROW LEVEL SECURITY;

--
-- Name: outlets outlets_delete_admin_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY outlets_delete_admin_or_dev ON public.outlets FOR DELETE TO authenticated USING ((public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev()));


--
-- Name: outlets outlets_insert_admin_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY outlets_insert_admin_or_dev ON public.outlets FOR INSERT TO authenticated WITH CHECK ((public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev()));


--
-- Name: outlets outlets_select_member_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY outlets_select_member_or_dev ON public.outlets FOR SELECT TO authenticated USING ((public.is_member(tenant_id) OR public.is_dev()));


--
-- Name: outlets outlets_update_admin_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY outlets_update_admin_or_dev ON public.outlets FOR UPDATE TO authenticated USING ((public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev())) WITH CHECK ((public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev()));


--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: payments payments_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_select_member ON public.payments FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: price_breaks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.price_breaks ENABLE ROW LEVEL SECURITY;

--
-- Name: price_breaks price_breaks_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY price_breaks_delete_admin ON public.price_breaks FOR DELETE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: price_breaks price_breaks_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY price_breaks_insert_admin ON public.price_breaks FOR INSERT TO authenticated WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: price_breaks price_breaks_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY price_breaks_select_member ON public.price_breaks FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: price_breaks price_breaks_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY price_breaks_update_admin ON public.price_breaks FOR UPDATE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text])) WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: price_tiers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.price_tiers ENABLE ROW LEVEL SECURITY;

--
-- Name: price_tiers price_tiers_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY price_tiers_delete_admin ON public.price_tiers FOR DELETE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: price_tiers price_tiers_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY price_tiers_insert_admin ON public.price_tiers FOR INSERT TO authenticated WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: price_tiers price_tiers_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY price_tiers_select_member ON public.price_tiers FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: price_tiers price_tiers_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY price_tiers_update_admin ON public.price_tiers FOR UPDATE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text])) WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: product_prices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_prices ENABLE ROW LEVEL SECURITY;

--
-- Name: product_prices product_prices_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_prices_delete_admin ON public.product_prices FOR DELETE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: product_prices product_prices_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_prices_insert_admin ON public.product_prices FOR INSERT TO authenticated WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: product_prices product_prices_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_prices_select_member ON public.product_prices FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: product_prices product_prices_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_prices_update_admin ON public.product_prices FOR UPDATE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text])) WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: product_units; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_units ENABLE ROW LEVEL SECURITY;

--
-- Name: product_units product_units_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_units_delete_admin ON public.product_units FOR DELETE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: product_units product_units_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_units_insert_admin ON public.product_units FOR INSERT TO authenticated WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: product_units product_units_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_units_select_member ON public.product_units FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: product_units product_units_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_units_update_admin ON public.product_units FOR UPDATE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text])) WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: products products_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_delete_admin ON public.products FOR DELETE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: products products_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_insert_admin ON public.products FOR INSERT TO authenticated WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: products products_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_select_member ON public.products FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: products products_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_update_admin ON public.products FOR UPDATE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text])) WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: receivables; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.receivables ENABLE ROW LEVEL SECURITY;

--
-- Name: receivables receivables_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY receivables_select_member ON public.receivables FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: sale_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;

--
-- Name: sale_items sale_items_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sale_items_select_member ON public.sale_items FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: sale_return_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sale_return_items ENABLE ROW LEVEL SECURITY;

--
-- Name: sale_return_items sale_return_items_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sale_return_items_select_member ON public.sale_return_items FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: sale_returns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sale_returns ENABLE ROW LEVEL SECURITY;

--
-- Name: sale_returns sale_returns_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sale_returns_select_member ON public.sale_returns FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: sales; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

--
-- Name: sales sales_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sales_select_member ON public.sales FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: stock_levels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_levels ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_levels stock_levels_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stock_levels_select_member ON public.stock_levels FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: stock_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_movements stock_movements_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stock_movements_select_member ON public.stock_movements FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: stock_opname_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_opname_items ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_opname_items stock_opname_items_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stock_opname_items_select_member ON public.stock_opname_items FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: stock_opnames; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_opnames ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_opnames stock_opnames_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stock_opnames_select_member ON public.stock_opnames FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: suppliers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- Name: suppliers suppliers_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY suppliers_delete_admin ON public.suppliers FOR DELETE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: suppliers suppliers_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY suppliers_insert_admin ON public.suppliers FOR INSERT TO authenticated WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: suppliers suppliers_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY suppliers_select_member ON public.suppliers FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: suppliers suppliers_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY suppliers_update_admin ON public.suppliers FOR UPDATE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text])) WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: tenants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

--
-- Name: tenants tenants_select_member_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenants_select_member_or_dev ON public.tenants FOR SELECT TO authenticated USING ((public.is_member(id) OR public.is_dev()));


--
-- Name: tenants tenants_update_admin_or_dev; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenants_update_admin_or_dev ON public.tenants FOR UPDATE TO authenticated USING ((public.has_role(id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev())) WITH CHECK ((public.has_role(id, ARRAY['owner'::text, 'admin'::text]) OR public.is_dev()));


--
-- Name: units; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;

--
-- Name: units units_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY units_delete_admin ON public.units FOR DELETE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: units units_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY units_insert_admin ON public.units FOR INSERT TO authenticated WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- Name: units units_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY units_select_member ON public.units FOR SELECT TO authenticated USING (public.is_member(tenant_id));


--
-- Name: units units_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY units_update_admin ON public.units FOR UPDATE TO authenticated USING (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text])) WITH CHECK (public.has_role(tenant_id, ARRAY['owner'::text, 'admin'::text]));


--
-- PostgreSQL database dump complete
--


