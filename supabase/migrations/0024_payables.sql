-- 0024: payables + payable_payments (T6.3)
-- Hutang supplier + pembayaran. Mirror dari piutang (receivables).
-- Tabel ditulis hanya lewat RPC security definer (tidak ada grant tulis langsung).

create table public.payables (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  outlet_id uuid not null,
  supplier_id uuid not null,
  purchase_order_id uuid,
  client_uuid uuid not null,
  amount bigint not null check (amount > 0),
  due_date date not null,
  status text not null check (status in ('open', 'partial', 'paid')),
  total_paid bigint not null default 0 check (total_paid >= 0),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, client_uuid),
  constraint payable_outlet_same_tenant
    foreign key (tenant_id, outlet_id) references public.outlets (tenant_id, id),
  constraint payable_supplier_same_tenant
    foreign key (tenant_id, supplier_id) references public.suppliers (tenant_id, id),
  constraint payable_po_same_tenant
    foreign key (tenant_id, purchase_order_id) references public.purchase_orders (tenant_id, id)
);

create index payable_tenant_created_idx
  on public.payables (tenant_id, created_at desc);
create index payable_tenant_supplier_idx
  on public.payables (tenant_id, supplier_id);
create index payable_tenant_status_idx
  on public.payables (tenant_id, status);

create table public.payable_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  payable_id uuid not null,
  client_uuid uuid not null,
  amount bigint not null check (amount > 0),
  method text not null check (method in ('tunai', 'transfer', 'qris', 'debit')),
  reference text,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, client_uuid),
  constraint payable_payment_payable_same_tenant
    foreign key (tenant_id, payable_id) references public.payables (tenant_id, id) on delete cascade
);

create index payable_payment_payable_idx
  on public.payable_payments (tenant_id, payable_id);
create index payable_payment_tenant_date_idx
  on public.payable_payments (tenant_id, paid_at desc);

alter table public.payables enable row level security;
alter table public.payable_payments enable row level security;

revoke all on public.payables from anon, authenticated;
revoke all on public.payable_payments from anon, authenticated;

grant select on public.payables to authenticated;
grant select on public.payable_payments to authenticated;

create policy payable_select_member on public.payables
  for select to authenticated using (public.is_member(tenant_id));
create policy payable_payment_select_member on public.payable_payments
  for select to authenticated using (public.is_member(tenant_id));

create trigger payable_updated_at before update on public.payables
  for each row execute function public.set_updated_at();
create trigger payable_created_by before insert on public.payables
  for each row execute function public.set_created_by();
create trigger payable_tenant_id_immutable before update on public.payables
  for each row execute function public.prevent_tenant_change();

create trigger payable_payment_created_by before insert on public.payable_payments
  for each row execute function public.set_created_by();
create trigger payable_payment_tenant_id_immutable before update on public.payable_payments
  for each row execute function public.prevent_tenant_change();

-- create_payable: catat hutang baru dari penerimaan barang / PO.
create function public.create_payable(
  p_client_uuid uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_supplier_id uuid,
  p_purchase_order_id uuid,
  p_amount bigint,
  p_due_date date,
  p_note text
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_payable_id uuid;
    v_payable record;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk membuat hutang' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    select id, client_uuid, amount, status
      into v_payable
    from public.payables
    where tenant_id = p_tenant_id and client_uuid = p_client_uuid;

    if v_payable.id is not null then
      return jsonb_build_object(
        'payable_id', v_payable.id,
        'client_uuid', v_payable.client_uuid,
        'amount', v_payable.amount,
        'status', v_payable.status,
        'idempotent', true
      );
    end if;

    if not public.has_role(p_tenant_id, array['owner', 'admin']) then
      raise exception 'Hanya owner/admin yang boleh mencatat hutang' using errcode = '42501';
    end if;

    if p_amount is null or p_amount <= 0 then
      raise exception 'Jumlah hutang harus lebih dari 0' using errcode = 'P0001';
    end if;
    if p_due_date is null then
      raise exception 'Tanggal jatuh tempo wajib diisi' using errcode = 'P0001';
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

    if p_purchase_order_id is not null then
      if not exists (
        select 1 from public.purchase_orders
        where tenant_id = p_tenant_id and id = p_purchase_order_id
      ) then
        raise exception 'Purchase order tidak ditemukan' using errcode = 'P0001';
      end if;
    end if;

    insert into public.payables (
      tenant_id, outlet_id, supplier_id, purchase_order_id, client_uuid,
      amount, due_date, status, total_paid, note
    ) values (
      p_tenant_id, p_outlet_id, p_supplier_id, p_purchase_order_id,
      p_client_uuid, p_amount, p_due_date, 'open', 0,
      nullif(btrim(coalesce(p_note, '')), '')
    )
    returning id into v_payable_id;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, after, user_id
    ) values (
      p_tenant_id, 'payable', v_payable_id, 'create',
      jsonb_build_object(
        'supplier_id', p_supplier_id,
        'purchase_order_id', p_purchase_order_id,
        'amount', p_amount,
        'due_date', p_due_date,
        'status', 'open'
      ),
      auth.uid()
    );

    return jsonb_build_object(
      'payable_id', v_payable_id,
      'client_uuid', p_client_uuid,
      'amount', p_amount,
      'status', 'open',
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public.create_payable(
  uuid, uuid, uuid, uuid, uuid, bigint, date, text
) from public, anon;
grant execute on function public.create_payable(
  uuid, uuid, uuid, uuid, uuid, bigint, date, text
) to authenticated;

-- pay_payable: bayar hutang (cicilan). Atomik + idempoten via client_uuid.
create function public.pay_payable(
  p_tenant_id uuid,
  p_payable_id uuid,
  p_client_uuid uuid,
  p_amount bigint,
  p_method text,
  p_reference text
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_payable record;
    v_payment record;
    v_new_total_paid bigint;
    v_new_status text;
  begin
    if auth.uid() is null then
      raise exception 'Harus login untuk membayar hutang' using errcode = '28000';
    end if;
    if p_client_uuid is null then
      raise exception 'client_uuid wajib diisi' using errcode = 'P0001';
    end if;

    -- Idempotensi: pembayaran dengan client_uuid sama sudah diproses.
    select id, payable_id, amount, paid_at
      into v_payment
    from public.payable_payments
    where tenant_id = p_tenant_id and client_uuid = p_client_uuid;

    if v_payment.id is not null then
      select status into v_new_status
      from public.payables
      where tenant_id = p_tenant_id and id = v_payment.payable_id;

      return jsonb_build_object(
        'payment_id', v_payment.id,
        'payable_id', v_payment.payable_id,
        'amount', v_payment.amount,
        'paid_at', v_payment.paid_at,
        'total_paid', (select total_paid from public.payables where tenant_id = p_tenant_id and id = v_payment.payable_id),
        'status', v_new_status,
        'idempotent', true
      );
    end if;

    if not public.has_role(p_tenant_id, array['owner', 'admin']) then
      raise exception 'Hanya owner/admin yang boleh membayar hutang' using errcode = '42501';
    end if;

    if p_amount is null or p_amount <= 0 then
      raise exception 'Nominal pembayaran harus lebih dari 0' using errcode = 'P0001';
    end if;

    select id, amount, total_paid, status
      into v_payable
    from public.payables
    where tenant_id = p_tenant_id and id = p_payable_id;

    if not found then
      raise exception 'Hutang tidak ditemukan' using errcode = 'P0001';
    end if;
    if v_payable.status = 'paid' then
      raise exception 'Hutang sudah lunas' using errcode = 'P0001';
    end if;

    v_new_total_paid := v_payable.total_paid + p_amount;
    if v_new_total_paid >= v_payable.amount then
      v_new_status := 'paid';
    else
      v_new_status := 'partial';
    end if;

    insert into public.payable_payments (
      tenant_id, payable_id, client_uuid, amount, method, reference
    ) values (
      p_tenant_id, p_payable_id, p_client_uuid, p_amount, p_method,
      nullif(btrim(coalesce(p_reference, '')), '')
    );

    update public.payables
    set total_paid = v_new_total_paid, status = v_new_status
    where tenant_id = p_tenant_id and id = p_payable_id;

    insert into public.audit_logs (
      tenant_id, entity, entity_id, action, after, user_id
    ) values (
      p_tenant_id, 'payable_payment', p_payable_id, 'create',
      jsonb_build_object(
        'payable_id', p_payable_id,
        'amount', p_amount,
        'method', p_method,
        'reference', nullif(btrim(coalesce(p_reference, '')), ''),
        'total_paid', v_new_total_paid,
        'status', v_new_status
      ),
      auth.uid()
    );

    return jsonb_build_object(
      'payment_id', null,
      'payable_id', p_payable_id,
      'amount', p_amount,
      'paid_at', now(),
      'total_paid', v_new_total_paid,
      'status', v_new_status,
      'idempotent', false
    );
  end;
  $$;

revoke execute on function public.pay_payable(
  uuid, uuid, uuid, bigint, text, text
) from public, anon;
grant execute on function public.pay_payable(
  uuid, uuid, uuid, bigint, text, text
) to authenticated;
