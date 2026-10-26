-- 0014: shift kasir (T4.1)
-- Buka kasir mencatat modal awal; tutup kasir menghitung expected cash dan
-- selisih. Semua tulis lewat RPC security definer (idempoten via client_uuid).
-- Penjualan tunai & pengeluaran belum ada di fase ini; expected_cash saat ini
-- = modal awal. Saat modul penjualan/kas tersedia, close_cash_shift diganti
-- lewat migrasi baru (jangan edit migrasi ini).

create table public.cash_shifts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  outlet_id uuid not null,
  cashier_id uuid not null,
  opening_cash bigint not null check (opening_cash >= 0),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  closing_cash_counted bigint check (closing_cash_counted >= 0),
  expected_cash bigint check (expected_cash >= 0),
  difference bigint,
  note text,
  client_uuid uuid not null,
  close_client_uuid uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, client_uuid),
  unique (tenant_id, id),
  constraint cash_shifts_outlet_same_tenant
    foreign key (tenant_id, outlet_id) references public.outlets (tenant_id, id),
  constraint cash_shifts_closed_fields check (
    (closed_at is null and closing_cash_counted is null
      and expected_cash is null and difference is null)
    or
    (closed_at is not null and closing_cash_counted is not null
      and expected_cash is not null and difference is not null)
  )
);

create index cash_shifts_tenant_opened_idx
  on public.cash_shifts (tenant_id, opened_at desc);
create index cash_shifts_cashier_idx
  on public.cash_shifts (tenant_id, cashier_id, opened_at desc);

-- Satu kasir hanya boleh punya satu shift terbuka per outlet.
create unique index cash_shifts_one_open_key
  on public.cash_shifts (tenant_id, outlet_id, cashier_id)
  where closed_at is null;

alter table public.cash_shifts enable row level security;

-- Baca boleh untuk semua member tenant. Tulis hanya lewat RPC.
revoke all on public.cash_shifts from anon, authenticated;
grant select on public.cash_shifts to authenticated;

create policy cash_shifts_select_member on public.cash_shifts
  for select to authenticated using (public.is_member(tenant_id));

create trigger cash_shifts_updated_at before update on public.cash_shifts
  for each row execute function public.set_updated_at();
create trigger cash_shifts_created_by before insert on public.cash_shifts
  for each row execute function public.set_created_by();
create trigger cash_shifts_tenant_id_immutable before update on public.cash_shifts
  for each row execute function public.prevent_tenant_change();

-- Buka shift: kasir (atau owner/admin yang merangkap kasir) mencatat modal awal.
create function public.open_cash_shift(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_opening_cash bigint,
  p_client_uuid uuid
) returns uuid
  language plpgsql
  security definer
  set search_path = public
  as $$
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

revoke execute on function public.open_cash_shift(uuid, uuid, bigint, uuid)
  from public, anon;
grant execute on function public.open_cash_shift(uuid, uuid, bigint, uuid)
  to authenticated;

-- Tutup shift: kasir pemilik shift atau owner/admin. Selisih disimpan apa adanya.
create function public.close_cash_shift(
  p_shift_id uuid,
  p_closing_cash_counted bigint,
  p_note text,
  p_client_uuid uuid
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
  as $$
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

    -- expected = modal awal + penjualan tunai - kas keluar.
    -- Penjualan tunai/kas keluar belum ada (T4.4+); sementara hanya modal awal.
    v_expected := v_shift.opening_cash;
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

revoke execute on function public.close_cash_shift(uuid, bigint, text, uuid)
  from public, anon;
grant execute on function public.close_cash_shift(uuid, bigint, text, uuid)
  to authenticated;
