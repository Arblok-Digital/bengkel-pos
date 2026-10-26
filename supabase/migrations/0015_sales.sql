-- 0015: penjualan (T4.2)
-- Tabel sales, sale_items, payments, receivables, audit_logs + RPC create_sale.
-- Aturan: uang integer (bigint), stok hanya lewat stock_movements, total
-- dihitung server, idempoten via client_uuid, harga & HPP disalin ke item.

-- ═══════════════════════════════════════════════════════════════════════════════
-- Tabel
-- ═══════════════════════════════════════════════════════════════════════════════

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  outlet_id uuid not null,
  invoice_no text not null,
  client_uuid uuid not null,
  customer_id uuid,
  vehicle_id uuid,
  work_order_id uuid,
  status text not null check (status in ('draft', 'paid', 'partial', 'credit', 'void')),
  subtotal bigint not null check (subtotal >= 0),
  discount bigint not null default 0 check (discount >= 0),
  tax bigint not null default 0 check (tax >= 0),
  total bigint not null check (total >= 0),
  paid_amount bigint not null check (paid_amount >= 0),
  change_amount bigint not null default 0 check (change_amount >= 0),
  cashier_id uuid not null,
  shift_id uuid,
  sold_at timestamptz not null default now(),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, client_uuid),
  unique (tenant_id, outlet_id, invoice_no),
  constraint sales_outlet_same_tenant
    foreign key (tenant_id, outlet_id) references public.outlets (tenant_id, id),
  constraint sales_customer_same_tenant
    foreign key (tenant_id, customer_id) references public.customers (tenant_id, id),
  constraint sales_shift_same_tenant
    foreign key (tenant_id, shift_id) references public.cash_shifts (tenant_id, id)
);

create index sales_tenant_sold_idx
  on public.sales (tenant_id, sold_at desc);
create index sales_tenant_outlet_idx
  on public.sales (tenant_id, outlet_id, sold_at desc);
create index sales_customer_idx
  on public.sales (tenant_id, customer_id, sold_at desc);
create index sales_shift_idx
  on public.sales (tenant_id, shift_id);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  sale_id uuid not null,
  product_id uuid not null,
  unit_id uuid not null,
  qty numeric not null check (qty > 0),
  qty_base numeric not null check (qty_base > 0),
  unit_price bigint not null check (unit_price >= 0),
  unit_cost bigint not null default 0 check (unit_cost >= 0),
  discount bigint not null default 0 check (discount >= 0),
  line_total bigint not null check (line_total >= 0),
  note text,
  mechanic_id uuid,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint sale_items_sale_same_tenant
    foreign key (tenant_id, sale_id) references public.sales (tenant_id, id) on delete cascade,
  constraint sale_items_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id),
  constraint sale_items_unit_same_tenant
    foreign key (tenant_id, unit_id) references public.units (tenant_id, id)
);

create index sale_items_sale_idx
  on public.sale_items (tenant_id, sale_id);
create index sale_items_product_idx
  on public.sale_items (tenant_id, product_id);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  sale_id uuid not null,
  method text not null check (method in ('tunai', 'transfer', 'qris', 'debit', 'kredit_tempo')),
  amount bigint not null check (amount > 0),
  reference text,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint payments_sale_same_tenant
    foreign key (tenant_id, sale_id) references public.sales (tenant_id, id) on delete cascade
);

create index payments_sale_idx
  on public.payments (tenant_id, sale_id);

create table public.receivables (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  sale_id uuid not null,
  customer_id uuid not null,
  amount bigint not null check (amount > 0),
  due_date date not null,
  status text not null default 'open' check (status in ('open', 'partial', 'paid')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, sale_id),
  unique (tenant_id, id),
  constraint receivables_sale_same_tenant
    foreign key (tenant_id, sale_id) references public.sales (tenant_id, id),
  constraint receivables_customer_same_tenant
    foreign key (tenant_id, customer_id) references public.customers (tenant_id, id)
);

create index receivables_customer_idx
  on public.receivables (tenant_id, customer_id, due_date);
create index receivables_due_date_idx
  on public.receivables (tenant_id, due_date, status);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  entity text not null,
  entity_id uuid not null,
  action text not null,
  before jsonb,
  after jsonb,
  reason text,
  user_id uuid,
  created_at timestamptz not null default now()
);

create index audit_logs_entity_idx
  on public.audit_logs (tenant_id, entity, created_at desc);

-- ═══════════════════════════════════════════════════════════════════════════════
-- RLS + trigger
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.payments enable row level security;
alter table public.receivables enable row level security;
alter table public.audit_logs enable row level security;

-- Tulis hanya lewat RPC security definer.
revoke all on public.sales from anon, authenticated;
revoke all on public.sale_items from anon, authenticated;
revoke all on public.payments from anon, authenticated;
revoke all on public.receivables from anon, authenticated;
revoke all on public.audit_logs from anon, authenticated;

grant select on public.sales to authenticated;
grant select on public.sale_items to authenticated;
grant select on public.payments to authenticated;
grant select on public.receivables to authenticated;
grant select on public.audit_logs to authenticated;

create policy sales_select_member on public.sales
  for select to authenticated using (public.is_member(tenant_id));
create policy sale_items_select_member on public.sale_items
  for select to authenticated using (public.is_member(tenant_id));
create policy payments_select_member on public.payments
  for select to authenticated using (public.is_member(tenant_id));
create policy receivables_select_member on public.receivables
  for select to authenticated using (public.is_member(tenant_id));
create policy audit_logs_select_member on public.audit_logs
  for select to authenticated using (public.is_member(tenant_id));

create trigger sales_updated_at before update on public.sales
  for each row execute function public.set_updated_at();
create trigger sales_created_by before insert on public.sales
  for each row execute function public.set_created_by();
create trigger sales_tenant_id_immutable before update on public.sales
  for each row execute function public.prevent_tenant_change();

create trigger receivables_updated_at before update on public.receivables
  for each row execute function public.set_updated_at();
create trigger receivables_created_by before insert on public.receivables
  for each row execute function public.set_created_by();
create trigger receivables_tenant_id_immutable before update on public.receivables
  for each row execute function public.prevent_tenant_change();

-- ═══════════════════════════════════════════════════════════════════════════════
-- Nomor invoice: INV-YYYYMMDD-#### per outlet per hari
-- ═══════════════════════════════════════════════════════════════════════════════

create function public.generate_invoice_no(
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

revoke execute on function public.generate_invoice_no(uuid, uuid) from public, anon;
grant execute on function public.generate_invoice_no(uuid, uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- create_sale: atomik + idempoten
-- ═══════════════════════════════════════════════════════════════════════════════

create function public.create_sale(
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

revoke execute on function public.create_sale(
  uuid, uuid, uuid, uuid, jsonb, jsonb, uuid, text, uuid, uuid
) from public, anon;
grant execute on function public.create_sale(
  uuid, uuid, uuid, uuid, jsonb, jsonb, uuid, text, uuid, uuid
) to authenticated;
