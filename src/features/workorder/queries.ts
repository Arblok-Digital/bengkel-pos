import { createClient } from "@/lib/supabase/server";
import { mulQty } from "@/lib/money";

export type WorkOrderRow = {
  id: string;
  tenantId: string;
  outletId: string;
  woNo: string;
  queueNo: number;
  customerId: string;
  customerName: string;
  vehicleId: string;
  vehiclePlate: string;
  odometer: number | null;
  complaint: string;
  diagnosis: string | null;
  status: string;
  mechanicId: string | null;
  mechanicName: string | null;
  estimateTotal: number;
  saleId: string | null;
  createdAt: string;
};

export type WorkOrderItemRow = {
  id: string;
  workOrderId: string;
  productId: string;
  productName: string;
  unitId: string;
  unitName: string;
  qty: number;
  qtyBase: number;
  unitPrice: number;
  lineTotal: number;
  note: string | null;
};

export type WorkOrdersPageData = {
  tenantId: string;
  tenantName: string;
  businessType: string;
  canWrite: boolean;
  outletId: string;
  workOrders: WorkOrderRow[];
};

export type WorkOrderDetail = {
  workOrder: WorkOrderRow;
  items: WorkOrderItemRow[];
};

export type WorkOrderOption = { id: string; woNo: string; queueNo: number; status: string; customerName: string };
export type MechanicOption = { id: string; name: string };

const WO_COLUMNS =
  "id, tenant_id, outlet_id, wo_no, queue_no, customer_id, vehicle_id, odometer, complaint, diagnosis, status, mechanic_id, estimate_total, sale_id, created_at";

function mapWorkOrder(row: {
  id: string;
  tenant_id: string;
  outlet_id: string;
  wo_no: string;
  queue_no: number;
  customer_id: string;
  vehicle_id: string;
  odometer: number | null;
  complaint: string;
  diagnosis: string | null;
  status: string;
  mechanic_id: string | null;
  estimate_total: number | null;
  sale_id: string | null;
  created_at: string;
  customers: { name: string } | null;
  vehicles: { plate_no: string } | null;
}): WorkOrderRow {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    outletId: row.outlet_id,
    woNo: row.wo_no,
    queueNo: row.queue_no,
    customerId: row.customer_id,
    customerName: row.customers?.name ?? "—",
    vehicleId: row.vehicle_id,
    vehiclePlate: row.vehicles?.plate_no ?? "—",
    odometer: row.odometer,
    complaint: row.complaint,
    diagnosis: row.diagnosis,
    status: row.status,
    mechanicId: row.mechanic_id,
    mechanicName: "—",
    estimateTotal: Number(row.estimate_total ?? 0),
    saleId: row.sale_id,
    createdAt: row.created_at,
  };
}

export async function getWorkOrdersPage(): Promise<WorkOrdersPageData | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: memberships, error } = await supabase
    .from("memberships")
    .select("tenant_id, role, tenants(id, name, business_type)")
    .eq("user_id", user.id)
    .eq("active", true)
    .limit(1);

  if (error || !memberships || memberships.length === 0) return null;

  const membership = memberships[0];
  const tenant = Array.isArray(membership.tenants)
    ? membership.tenants[0]
    : membership.tenants;

  if (!tenant) return null;

  const { data } = await supabase
    .from("work_orders")
    .select(
      `${WO_COLUMNS}, customers(name), vehicles(plate_no)`
    )
    .eq("tenant_id", membership.tenant_id)
    .order("queue_no", { ascending: true });

  const { data: outlet } = await supabase
    .from("outlets")
    .select("id")
    .eq("tenant_id", membership.tenant_id)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  return {
    tenantId: membership.tenant_id,
    tenantName: tenant.name,
    businessType: tenant.business_type,
    canWrite: ["owner", "admin", "mekanik"].includes(membership.role),
    outletId: outlet?.id ?? "",
    workOrders: (data ?? []).map((row) => {
      const r = row as unknown as {
        id: string;
        tenant_id: string;
        outlet_id: string;
        wo_no: string;
        queue_no: number;
        customer_id: string;
        vehicle_id: string;
        odometer: number | null;
        complaint: string;
        diagnosis: string | null;
        status: string;
        mechanic_id: string | null;
        estimate_total: number | null;
        sale_id: string | null;
        created_at: string;
        customers: { name: string } | null;
        vehicles: { plate_no: string } | null;
      };
      return mapWorkOrder(r);
    }),
  };
}

export async function getWorkOrderDetail(
  woId: string
): Promise<WorkOrderDetail | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: memberships } = await supabase
    .from("memberships")
    .select("tenant_id")
    .eq("user_id", user.id)
    .eq("active", true)
    .limit(1);

  if (!memberships || memberships.length === 0) return null;

  const tenantId = memberships[0].tenant_id;

  const { data: wo } = await supabase
    .from("work_orders")
    .select(
      `${WO_COLUMNS}, customers(name), vehicles(plate_no, brand, model)`
    )
    .eq("tenant_id", tenantId)
    .eq("id", woId)
    .maybeSingle();

  if (!wo) return null;

  const { data: items } = await supabase
    .from("work_order_items")
    .select(
      "id, work_order_id, product_id, unit_id, qty, qty_base, unit_price, line_total, note, products(name), units(name)"
    )
    .eq("tenant_id", tenantId)
    .eq("work_order_id", woId)
    .order("created_at", { ascending: true });

  const r = wo as unknown as {
    id: string;
    tenant_id: string;
    outlet_id: string;
    wo_no: string;
    queue_no: number;
    customer_id: string;
    vehicle_id: string;
    odometer: number | null;
    complaint: string;
    diagnosis: string | null;
    status: string;
    mechanic_id: string | null;
    estimate_total: number | null;
    sale_id: string | null;
    created_at: string;
    customers: { name: string } | null;
    vehicles: { plate_no: string; brand: string | null; model: string | null } | null;
  };

  const workOrder: WorkOrderRow = {
    id: r.id,
    tenantId: r.tenant_id,
    outletId: r.outlet_id,
    woNo: r.wo_no,
    queueNo: r.queue_no,
    customerId: r.customer_id,
    customerName: r.customers?.name ?? "—",
    vehicleId: r.vehicle_id,
    vehiclePlate: r.vehicles?.plate_no ?? "—",
    odometer: r.odometer,
    complaint: r.complaint,
    diagnosis: r.diagnosis,
    status: r.status,
    mechanicId: r.mechanic_id,
    mechanicName: "—",
    estimateTotal: Number(r.estimate_total ?? 0),
    saleId: r.sale_id,
    createdAt: r.created_at,
  };

  const itemRows: WorkOrderItemRow[] = (items ?? []).map((it) => {
    const i = it as unknown as {
      id: string;
      work_order_id: string;
      product_id: string;
      unit_id: string;
      qty: number;
      qty_base: number;
      unit_price: number;
      line_total: number;
      note: string | null;
      products: { name: string } | null;
      units: { name: string } | null;
    };
    return {
      id: i.id,
      workOrderId: i.work_order_id,
      productId: i.product_id,
      productName: i.products?.name ?? "—",
      unitId: i.unit_id,
      unitName: i.units?.name ?? "—",
      qty: i.qty,
      qtyBase: i.qty_base,
      unitPrice: i.unit_price,
      lineTotal: i.line_total,
      note: i.note,
    };
  });

  return { workOrder, items: itemRows };
}

export async function getWorkOrderOptions(): Promise<WorkOrderOption[]> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return [];

  const { data: memberships } = await supabase
    .from("memberships")
    .select("tenant_id")
    .eq("user_id", user.id)
    .eq("active", true)
    .limit(1);

  if (!memberships || memberships.length === 0) return [];

  const { data } = await supabase
    .from("work_orders")
    .select("id, wo_no, queue_no, status, customers(name)")
    .eq("tenant_id", memberships[0].tenant_id)
    .order("queue_no", { ascending: true });

  return (data ?? []).map((row) => ({
    id: row.id,
    woNo: row.wo_no,
    queueNo: row.queue_no,
    status: row.status,
    customerName: (row as unknown as { customers?: { name: string } | null })
      .customers?.name ?? "—",
  }));
}

export type CustomerOption = { id: string; name: string };

export async function getCustomerOptions(): Promise<CustomerOption[]> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return [];

  const { data: memberships } = await supabase
    .from("memberships")
    .select("tenant_id")
    .eq("user_id", user.id)
    .eq("active", true)
    .limit(1);

  if (!memberships || memberships.length === 0) return [];

  const { data } = await supabase
    .from("customers")
    .select("id, name")
    .eq("tenant_id", memberships[0].tenant_id)
    .eq("active", true)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
  }));
}

export async function getMechanicOptions(
  tenantId: string
): Promise<MechanicOption[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("memberships")
    .select("user_id, auth_users(email)")
    .eq("tenant_id", tenantId)
    .eq("role", "mekanik")
    .eq("active", true)
    .order("user_id");

  return (data ?? []).map((row) => ({
    id: row.user_id,
    name: (row as unknown as { auth_users?: { email: string } | null })
      .auth_users?.email ?? "—",
  }));
}

export type VehicleFormOption = {
  id: string;
  customerId: string;
  plateNo: string;
  label: string;
};

export type ProductUnitOption = { id: string; name: string; price: number };

export type ProductFormOption = {
  id: string;
  name: string;
  kind: string;
  sellPrice: number;
  units: ProductUnitOption[];
};

type QueryContext = {
  supabase: Awaited<ReturnType<typeof createClient>>;
  tenantId: string;
};

async function getQueryContext(): Promise<QueryContext | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: memberships } = await supabase
    .from("memberships")
    .select("tenant_id")
    .eq("user_id", user.id)
    .eq("active", true)
    .limit(1);

  if (!memberships || memberships.length === 0) return null;
  return { supabase, tenantId: memberships[0].tenant_id };
}

export async function getVehicleFormOptions(): Promise<VehicleFormOption[]> {
  const ctx = await getQueryContext();
  if (!ctx) return [];

  const { data } = await ctx.supabase
    .from("vehicles")
    .select("id, customer_id, plate_no, brand, model")
    .eq("tenant_id", ctx.tenantId)
    .eq("active", true)
    .order("plate_no");

  return (data ?? []).map((row) => {
    const r = row as unknown as {
      id: string;
      customer_id: string;
      plate_no: string;
      brand: string | null;
      model: string | null;
    };
    const detail = [r.brand, r.model].filter(Boolean).join(" ");
    return {
      id: r.id,
      customerId: r.customer_id,
      plateNo: r.plate_no,
      label: detail ? `${r.plate_no} — ${detail}` : r.plate_no,
    };
  });
}

export async function getProductFormOptions(): Promise<ProductFormOption[]> {
  const ctx = await getQueryContext();
  if (!ctx) return [];

  const [productsRes, productUnitsRes, unitsRes] = await Promise.all([
    ctx.supabase
      .from("products")
      .select("id, name, kind, base_unit_id, sell_price")
      .eq("tenant_id", ctx.tenantId)
      .eq("active", true)
      .order("name"),
    ctx.supabase
      .from("product_units")
      .select("product_id, unit_id, factor_to_base, sell_price")
      .eq("tenant_id", ctx.tenantId),
    ctx.supabase
      .from("units")
      .select("id, name")
      .eq("tenant_id", ctx.tenantId),
  ]);

  const unitNames = new Map(
    (unitsRes.data ?? []).map((row) => [row.id, row.name])
  );

  type ProductRow = {
    id: string;
    name: string;
    kind: string;
    base_unit_id: string | null;
    sell_price: number;
  };
  type ProductUnitRow = {
    product_id: string;
    unit_id: string;
    factor_to_base: number;
    sell_price: number | null;
  };

  const extraUnits = new Map<string, ProductUnitRow[]>();
  for (const row of (productUnitsRes.data ?? []) as ProductUnitRow[]) {
    const list = extraUnits.get(row.product_id) ?? [];
    list.push(row);
    extraUnits.set(row.product_id, list);
  }

  return ((productsRes.data ?? []) as ProductRow[]).map((product) => {
    const seen = new Set<string>();
    const units: ProductUnitOption[] = [];

    if (product.base_unit_id) {
      units.push({
        id: product.base_unit_id,
        name: unitNames.get(product.base_unit_id) ?? "satuan dasar",
        price: product.sell_price,
      });
      seen.add(product.base_unit_id);
    }

    for (const unit of extraUnits.get(product.id) ?? []) {
      if (seen.has(unit.unit_id)) continue;
      units.push({
        id: unit.unit_id,
        name: unitNames.get(unit.unit_id) ?? "satuan",
        price:
          unit.sell_price ?? mulQty(unit.factor_to_base, product.sell_price),
      });
      seen.add(unit.unit_id);
    }

    return {
      id: product.id,
      name: product.name,
      kind: product.kind,
      sellPrice: product.sell_price,
      units,
    };
  });
}
