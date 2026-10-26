-- 0003: tenant_id tidak boleh berpindah lewat UPDATE + trigger owner terakhir
--        dijalankan security definer.
-- Latar belakang: RLS WITH CHECK hanya melihat baris BARU, jadi user yang
-- admin/owner di dua tenant bisa memindahkan baris antar-tenant. RLS tidak bisa
-- membandingkan OLD vs NEW; karena itu dipakai trigger BEFORE UPDATE.

-- ─── helper: tolak perubahan tenant_id ───────────────────────────────────────
create function public.prevent_tenant_change() returns trigger
  language plpgsql
  set search_path = public
  as $$
  begin
    if new.tenant_id is distinct from old.tenant_id then
      raise exception 'tenant_id tidak boleh diubah (tabel %)', tg_table_name
        using errcode = 'P0001';
    end if;
    return new;
  end;
  $$;

revoke execute on function public.prevent_tenant_change() from public, anon, authenticated;

create trigger outlets_tenant_id_immutable
  before update on public.outlets
  for each row execute function public.prevent_tenant_change();

create trigger memberships_tenant_id_immutable
  before update on public.memberships
  for each row execute function public.prevent_tenant_change();

-- ─── protect_last_owner: security definer ────────────────────────────────────
-- Hitungan owner tidak boleh bergantung pada policy SELECT aktor; kalau policy
-- berubah, invarian "minimal satu owner aktif" bisa ikut melemah.
create or replace function public.protect_last_owner() returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
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

revoke execute on function public.protect_last_owner() from public, anon, authenticated;
