import { createClient } from "@/lib/supabase/server";

export type CatalogItem = {
  id: string;
  name: string;
};

export type CatalogData = {
  tenantId: string;
  tenantName: string;
  role: string;
  canWrite: boolean;
  categories: CatalogItem[];
  units: CatalogItem[];
};

/** Katalog tenant utama (membership aktif pertama). */
export async function getCatalog(): Promise<CatalogData | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: memberships, error } = await supabase
    .from("memberships")
    .select("tenant_id, role, tenants(id, name)")
    .eq("user_id", user.id)
    .eq("active", true)
    .limit(1);

  if (error || !memberships || memberships.length === 0) return null;

  const membership = memberships[0];
  const tenant = Array.isArray(membership.tenants)
    ? membership.tenants[0]
    : membership.tenants;

  if (!tenant) return null;

  const [{ data: categories }, { data: units }] = await Promise.all([
    supabase
      .from("categories")
      .select("id, name")
      .eq("tenant_id", membership.tenant_id)
      .order("name"),
    supabase
      .from("units")
      .select("id, name")
      .eq("tenant_id", membership.tenant_id)
      .order("name"),
  ]);

  return {
    tenantId: membership.tenant_id,
    tenantName: tenant.name,
    role: membership.role,
    canWrite: ["owner", "admin"].includes(membership.role),
    categories: categories ?? [],
    units: units ?? [],
  };
}
