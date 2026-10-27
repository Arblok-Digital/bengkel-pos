-- 0021: Tabel receivable_payments + RPC pay_receivable (T5.2)
-- Pembayaran cicilan piutang pelanggan.

create table public.receivable_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  receivable_id uuid not null,
  amount bigint not null check (amount > 0),
  method text not null check (method in ('tunai', 'transfer', 'qris', 'debit')),
  reference text,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid,
  constraint rp_receivable_same_tenant
    foreign key (tenant_id, receivable_id) references public.receivables (tenant_id, id)
);

create index rp_receivable_idx
  on public.receivable_payments (tenant_id, receivable_id, paid_at);

alter table public.receivable_payments enable row level security;

revoke all on public.receivable_payments from anon, authenticated;
grant select on public.receivable_payments to authenticated;

create policy rp_select_member on public.receivable_payments
  for select to authenticated
  using (public.is_member(tenant_id));

create trigger rp_created_by before insert on public.receivable_payments
  for each row execute function public.set_created_by();
create trigger rp_tenant_id_immutable before update on public.receivable_payments
  for each row execute function public.prevent_tenant_change();

-- ─── RPC pay_receivable ───────────────────────────────────────────────────────
-- Pembayaran cicilan piutang. Atomik: insert payment, update receivable status.

create or replace function public.pay_receivable(
  p_tenant_id uuid,
  p_receivable_id uuid,
  p_amount bigint,
  p_method text,
  p_reference text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rec record;
  v_total_paid bigint;
  v_remaining bigint;
  v_new_status text;
  v_payment_id uuid;
begin
  -- Validasi membership
  if not public.is_member(p_tenant_id) then
    raise exception 'Tidak berhak mengakses tenant ini'
      using errcode = '42501';
  end if;

  -- Ambil receivable + lock
  select * into v_rec
  from public.receivables
  where tenant_id = p_tenant_id and id = p_receivable_id
  for update;

  if not found then
    raise exception 'Piutang tidak ditemukan'
      using errcode = 'P0002';
  end if;

  if v_rec.status = 'paid' then
    raise exception 'Piutang sudah lunas'
      using errcode = 'P0001';
  end if;

  -- Hitung total sudah dibayar
  select coalesce(sum(amount), 0) into v_total_paid
  from public.receivable_payments
  where tenant_id = p_tenant_id and receivable_id = p_receivable_id;

  v_remaining := v_rec.amount - v_total_paid;

  if p_amount <= 0 then
    raise exception 'Nominal pembayaran harus lebih dari 0'
      using errcode = 'P0001';
  end if;

  if p_amount > v_remaining then
    raise exception 'Nominal pembayaran (%) melebihi sisa piutang (%)',
      p_amount, v_remaining
      using errcode = 'P0001';
  end if;

  -- Validasi method
  if p_method not in ('tunai', 'transfer', 'qris', 'debit') then
    raise exception 'Metode pembayaran tidak valid: %', p_method
      using errcode = 'P0001';
  end if;

  -- Insert payment
  insert into public.receivable_payments (
    tenant_id, receivable_id, amount, method, reference
  ) values (
    p_tenant_id, p_receivable_id, p_amount, p_method,
    nullif(btrim(coalesce(p_reference, '')), '')
  )
  returning id into v_payment_id;

  -- Update status
  v_total_paid := v_total_paid + p_amount;
  v_remaining := v_rec.amount - v_total_paid;

  v_new_status := case
    when v_remaining <= 0 then 'paid'
    else 'partial'
  end;

  update public.receivables
  set status = v_new_status
  where tenant_id = p_tenant_id and id = p_receivable_id;

  -- Audit
  insert into public.audit_logs (
    tenant_id, entity, entity_id, action, after, user_id
  ) values (
    p_tenant_id, 'receivable_payment', v_payment_id, 'create',
    jsonb_build_object(
      'receivable_id', p_receivable_id,
      'amount', p_amount,
      'method', p_method,
      'total_paid', v_total_paid,
      'remaining', v_remaining,
      'new_status', v_new_status
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'payment_id', v_payment_id,
    'total_paid', v_total_paid,
    'remaining', v_remaining,
    'status', v_new_status
  );
end;
$$;

revoke execute on function public.pay_receivable(uuid, uuid, bigint, text, text)
  from public, anon;
grant execute on function public.pay_receivable(uuid, uuid, bigint, text, text)
  to authenticated;
