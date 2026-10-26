import { createClient } from "@/lib/supabase/server";

export type BusinessType = "bengkel" | "toko_bangunan" | "both";

export type TenantSummary = {
  tenantId: string;
  tenantName: string;
  businessType: BusinessType;
  role: string;
  outlets: { id: string; name: string }[];
};

/** Daftar tenant aktif milik user yang sedang login. */
export async function getMyTenants(): Promise<TenantSummary[]> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return [];

  const { data, error } = await supabase
    .from("memberships")
    .select("tenant_id, role, tenants(id, name, business_type)")
    .eq("user_id", user.id)
    .eq("active", true)
    .order("created_at", { ascending: true });

  if (error || !data) return [];

  const tenantIds = data.map((row) => row.tenant_id);
  if (tenantIds.length === 0) return [];

  const { data: outlets } = await supabase
    .from("outlets")
    .select("id, tenant_id, name")
    .in("tenant_id", tenantIds)
    .order("name", { ascending: true });

  const outletsByTenant = new Map<string, { id: string; name: string }[]>();
  for (const outlet of outlets ?? []) {
    const list = outletsByTenant.get(outlet.tenant_id) ?? [];
    list.push({ id: outlet.id, name: outlet.name });
    outletsByTenant.set(outlet.tenant_id, list);
  }

  return data.flatMap((row) => {
    const tenant = Array.isArray(row.tenants) ? row.tenants[0] : row.tenants;
    if (!tenant) return [];
    return [
      {
        tenantId: tenant.id,
        tenantName: tenant.name,
        businessType: tenant.business_type as BusinessType,
        role: row.role,
        outlets: outletsByTenant.get(row.tenant_id) ?? [],
      },
    ];
  });
}
