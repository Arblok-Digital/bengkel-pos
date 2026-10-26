-- 0006: onboarding tenant (T1.2)
-- RPC atomik: buat tenant + outlet pertama + membership owner untuk pemanggil.
-- Idempoten lewat client_uuid (unik per tenant). Pembuatan tenant hanya lewat
-- RPC ini; tetap tanpa policy INSERT/DELETE di tabel tenants.

alter table public.tenants
  add column client_uuid uuid,
  add constraint tenants_client_uuid_key unique (client_uuid);

create function public.create_tenant(
  p_client_uuid uuid,
  p_name text,
  p_business_type text,
  p_outlet_name text
) returns table (tenant_id uuid, outlet_id uuid)
  language plpgsql
  security definer
  set search_path = public
  as $$
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

revoke execute on function public.create_tenant(uuid, text, text, text) from public, anon;
grant execute on function public.create_tenant(uuid, text, text, text) to authenticated;
