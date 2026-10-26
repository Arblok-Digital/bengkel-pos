import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export type ManagerTenant = {
  tenantId: string;
  tenantName: string;
  role: "owner" | "admin";
};

export type StaffMember = {
  userId: string;
  email: string;
  role: string;
  active: boolean;
  isSelf: boolean;
};

export async function getCurrentUserId(): Promise<string | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.id ?? null;
}

/** Tenant tempat user yang login berperan owner/admin. */
export async function getManagerTenants(): Promise<ManagerTenant[]> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return [];

  const { data, error } = await supabase
    .from("memberships")
    .select("tenant_id, role, tenants(id, name)")
    .eq("user_id", user.id)
    .eq("active", true)
    .in("role", ["owner", "admin"]);

  if (error || !data) return [];

  return data.flatMap((row) => {
    const tenant = Array.isArray(row.tenants) ? row.tenants[0] : row.tenants;
    if (!tenant) return [];
    return [
      {
        tenantId: tenant.id,
        tenantName: tenant.name,
        role: row.role as "owner" | "admin",
      },
    ];
  });
}

export async function hasManagerRole(): Promise<boolean> {
  return (await getManagerTenants()).length > 0;
}

/** Daftar staf satu tenant, lengkap dengan email dari auth.users. */
export async function getStaff(
  tenantId: string,
  currentUserId: string
): Promise<StaffMember[]> {
  const supabase = await createClient();
  const { data: rows, error } = await supabase
    .from("memberships")
    .select("user_id, role, active, created_at")
    .eq("tenant_id", tenantId)
    .order("created_at", { ascending: true });

  if (error || !rows) return [];

  const admin = createAdminClient();
  const { data: users } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });

  const emailById = new Map(
    (users?.users ?? []).map((u) => [u.id, u.email ?? "(tanpa email)"])
  );

  return rows.map((row) => ({
    userId: row.user_id,
    email: emailById.get(row.user_id) ?? "(tidak ditemukan)",
    role: row.role,
    active: row.active,
    isSelf: row.user_id === currentUserId,
  }));
}
