-- 0016: tutup shift menghitung uang tunai masuk dari penjualan (T4.2 lanjutan)
-- 0014 hanya memakai modal awal karena penjualan belum ada. Setelah create_sale
-- mencatat payments + shift_id, expected_cash =
--   modal awal + tunai bersih (tunai - kembalian) - kas keluar.
-- Kas keluar (expenses) belum ada; ditambahkan lewat migrasi baru saat modul kas.

create or replace function public.close_cash_shift(
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
    v_cash_in bigint := 0;
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

    -- Tunai bersih per penjualan = pembayaran tunai - kembalian (tidak negatif).
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
      where s.tenant_id = v_shift.tenant_id
        and s.shift_id = p_shift_id
        and s.status <> 'void'
      group by s.id, s.change_amount
    ) g;

    v_expected := v_shift.opening_cash + v_cash_in;
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
