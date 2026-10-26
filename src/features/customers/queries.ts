import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";

export type CustomerRow = {
  id: string;
  name: string;
  phone: string | null;
  address: string | null;
  tierId: string | null;
  tierName: string | null;
  creditLimit: number;
  notes: string | null;
  active: boolean;
};

export type CustomerTier = { id: string; name: string };

export type CustomersPageData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  tiers: CustomerTier[];
  customers: CustomerRow[];
};

const CUSTOMER_COLUMNS =
  "id, name, phone, address, tier_id, credit_limit, notes, active";

function mapCustomer(
  row: {
    id: string;
    name: string;
    phone: string | null;
    address: string | null;
    tier_id: string | null;
    credit_limit: number;
    notes: string | null;
    active: boolean;
  },
  tiers: CustomerTier[]
): CustomerRow {
  return {
    id: row.id,
    name: row.name,
    phone: row.phone,
    address: row.address,
    tierId: row.tier_id,
    tierName: tiers.find((t) => t.id === row.tier_id)?.name ?? null,
    creditLimit: row.credit_limit,
    notes: row.notes,
    active: row.active,
  };
}

export async function getCustomersPage(): Promise<CustomersPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const [tiersRes, customersRes] = await Promise.all([
    supabase
      .from("price_tiers")
      .select("id, name")
      .eq("tenant_id", base.tenantId)
      .order("name"),
    supabase
      .from("customers")
      .select(CUSTOMER_COLUMNS)
      .eq("tenant_id", base.tenantId)
      .order("name"),
  ]);

  const tiers = tiersRes.data ?? [];

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    tiers,
    customers: (customersRes.data ?? []).map((row) =>
      mapCustomer(row, tiers)
    ),
  };
}

export async function getCustomerForEdit(
  id: string
): Promise<CustomersPageData & { customer: CustomerRow } | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const [tiersRes, customerRes] = await Promise.all([
    supabase
      .from("price_tiers")
      .select("id, name")
      .eq("tenant_id", base.tenantId)
      .order("name"),
    supabase
      .from("customers")
      .select(CUSTOMER_COLUMNS)
      .eq("tenant_id", base.tenantId)
      .eq("id", id)
      .maybeSingle(),
  ]);

  if (!customerRes.data) return null;

  const tiers = tiersRes.data ?? [];

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    tiers,
    customers: [],
    customer: mapCustomer(customerRes.data, tiers),
  };
}
