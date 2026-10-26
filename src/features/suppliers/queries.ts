import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";

export type SupplierRow = {
  id: string;
  name: string;
  phone: string | null;
  address: string | null;
  paymentTermsDays: number;
  active: boolean;
};

export type SuppliersPageData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  suppliers: SupplierRow[];
};

const SUPPLIER_COLUMNS =
  "id, name, phone, address, payment_terms_days, active";

function mapSupplier(row: {
  id: string;
  name: string;
  phone: string | null;
  address: string | null;
  payment_terms_days: number;
  active: boolean;
}): SupplierRow {
  return {
    id: row.id,
    name: row.name,
    phone: row.phone,
    address: row.address,
    paymentTermsDays: row.payment_terms_days,
    active: row.active,
  };
}

export async function getSuppliersPage(): Promise<SuppliersPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("suppliers")
    .select(SUPPLIER_COLUMNS)
    .eq("tenant_id", base.tenantId)
    .order("name");

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    suppliers: (data ?? []).map(mapSupplier),
  };
}

export async function getSupplierForEdit(
  id: string
): Promise<SuppliersPageData & { supplier: SupplierRow } | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("suppliers")
    .select(SUPPLIER_COLUMNS)
    .eq("tenant_id", base.tenantId)
    .eq("id", id)
    .maybeSingle();

  if (!data) return null;

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    suppliers: [],
    supplier: mapSupplier(data),
  };
}
