import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";

export type VehicleRow = {
  id: string;
  tenantId: string;
  customerId: string;
  customerName: string;
  plateNo: string;
  brand: string | null;
  model: string | null;
  year: number | null;
  vin: string | null;
  lastOdometer: number | null;
  active: boolean;
};

export type VehiclesPageData = {
  tenantId: string;
  tenantName: string;
  businessType: string;
  canWrite: boolean;
  vehicles: VehicleRow[];
};

export type VehicleOption = { id: string; plateNo: string; customerName: string };

const VEHICLE_COLUMNS =
  "id, tenant_id, customer_id, plate_no, brand, model, year, vin, last_odometer, active";

function mapVehicle(row: {
  id: string;
  tenant_id: string;
  customer_id: string;
  plate_no: string;
  brand: string | null;
  model: string | null;
  year: number | null;
  vin: string | null;
  last_odometer: number | null;
  active: boolean;
  customers: { name: string } | null;
}): VehicleRow {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    customerId: row.customer_id,
    customerName: row.customers?.name ?? "—",
    plateNo: row.plate_no,
    brand: row.brand,
    model: row.model,
    year: row.year,
    vin: row.vin,
    lastOdometer: row.last_odometer,
    active: row.active,
  };
}

export async function getVehiclesPage(): Promise<VehiclesPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("vehicles")
    .select(`${VEHICLE_COLUMNS}, customers(name)`)
    .eq("tenant_id", base.tenantId)
    .order("plate_no");

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    businessType: base.businessType,
    canWrite: base.canWrite,
    vehicles: (data ?? []).map((row) => {
      const r = row as unknown as {
        id: string;
        tenant_id: string;
        customer_id: string;
        plate_no: string;
        brand: string | null;
        model: string | null;
        year: number | null;
        vin: string | null;
        last_odometer: number | null;
        active: boolean;
        customers: { name: string } | null;
      };
      return mapVehicle(r);
    }),
  };
}

export async function getVehicleForEdit(id: string): Promise<VehicleRow | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("vehicles")
    .select(`${VEHICLE_COLUMNS}, customers(name)`)
    .eq("tenant_id", base.tenantId)
    .eq("id", id)
    .maybeSingle();

  if (!data) return null;
  const r = data as unknown as {
    id: string;
    tenant_id: string;
    customer_id: string;
    plate_no: string;
    brand: string | null;
    model: string | null;
    year: number | null;
    vin: string | null;
    last_odometer: number | null;
    active: boolean;
    customers: { name: string } | null;
  };
  return mapVehicle(r);
}

export async function getVehicleOptions(): Promise<VehicleOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("vehicles")
    .select("id, plate_no, customers(name)")
    .eq("tenant_id", base.tenantId)
    .eq("active", true)
    .order("plate_no");

  return (data ?? []).map((row) => ({
    id: row.id,
    plateNo: row.plate_no,
    customerName: (row as unknown as { customers?: { name: string } | null })
      .customers?.name ?? "—",
  }));
}

export type CustomerOption = { id: string; name: string };

export async function getCustomerOptions(): Promise<CustomerOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("customers")
    .select("id, name")
    .eq("tenant_id", base.tenantId)
    .eq("active", true)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
  }));
}
