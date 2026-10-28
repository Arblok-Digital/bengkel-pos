import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";

export type PurchaseOrderRow = {
  id: string;
  poNo: string;
  supplierId: string;
  supplierName: string;
  outletId: string;
  outletName: string;
  status: "draft" | "ordered" | "partial" | "received" | "cancelled";
  total: number;
  createdAt: string;
};

export type PurchaseOrderItemRow = {
  id: string;
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

export type PurchaseOrderPageData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  purchaseOrders: PurchaseOrderRow[];
};

export type PurchaseOrderDetail = PurchaseOrderRow & {
  items: PurchaseOrderItemRow[];
  note: string | null;
};

function mapPurchaseOrder(row: {
  id: string;
  po_no: string;
  supplier_id: string;
  supplier_name: string | null;
  outlet_id: string;
  outlet_name: string | null;
  status: string;
  total: number | string;
  created_at: string;
}): PurchaseOrderRow {
  return {
    id: row.id,
    poNo: row.po_no,
    supplierId: row.supplier_id,
    supplierName: row.supplier_name ?? "—",
    outletId: row.outlet_id,
    outletName: row.outlet_name ?? "—",
    status: (row.status ?? "draft") as PurchaseOrderRow["status"],
    total: Number(row.total),
    createdAt: row.created_at,
  };
}

function mapPurchaseOrderItem(row: {
  id: string;
  product_id: string;
  product_name: string | null;
  unit_id: string;
  unit_name: string | null;
  qty: number | string;
  qty_base: number | string;
  unit_price: number | string;
  line_total: number | string;
  note: string | null;
}): PurchaseOrderItemRow {
  return {
    id: row.id,
    productId: row.product_id,
    productName: row.product_name ?? "—",
    unitId: row.unit_id,
    unitName: row.unit_name ?? "—",
    qty: Number(row.qty),
    qtyBase: Number(row.qty_base),
    unitPrice: Number(row.unit_price),
    lineTotal: Number(row.line_total),
    note: row.note,
  };
}

export async function getPurchaseOrdersPage(): Promise<PurchaseOrderPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("purchase_orders")
    .select(
      "id, po_no, supplier_id, outlet_id, status, total, created_at, suppliers(name), outlets(name)"
    )
    .eq("tenant_id", base.tenantId)
    .order("created_at", { ascending: false });

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    purchaseOrders: (data ?? []).map((row) => {
      const r = row as unknown as {
        id: string;
        po_no: string;
        supplier_id: string;
        outlet_id: string;
        status: string;
        total: number | string;
        created_at: string;
        suppliers: { name: string | null } | null;
        outlets: { name: string | null } | null;
      };
      return mapPurchaseOrder({
        ...r,
        supplier_name: r.suppliers?.name ?? null,
        outlet_name: r.outlets?.name ?? null,
      });
    }),
  };
}

export async function getPurchaseOrderForEdit(
  id: string
): Promise<PurchaseOrderDetail | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data: po } = await supabase
    .from("purchase_orders")
    .select(
      "id, po_no, supplier_id, outlet_id, status, total, note, created_at, suppliers(name), outlets(name)"
    )
    .eq("tenant_id", base.tenantId)
    .eq("id", id)
    .maybeSingle();

  if (!po) return null;

  const { data: items } = await supabase
    .from("purchase_order_items")
    .select(
      "id, product_id, unit_id, qty, qty_base, unit_price, line_total, note, products(name), units(name)"
    )
    .eq("tenant_id", base.tenantId)
    .eq("purchase_order_id", id)
    .order("created_at", { ascending: true });

  const r = po as unknown as {
    id: string;
    po_no: string;
    supplier_id: string;
    outlet_id: string;
    status: string;
    total: number | string;
    note: string | null;
    created_at: string;
    suppliers: { name: string | null } | null;
    outlets: { name: string | null } | null;
  };

  const main: PurchaseOrderRow = mapPurchaseOrder({
    ...r,
    supplier_name: r.suppliers?.name ?? null,
    outlet_name: r.outlets?.name ?? null,
  });

  const itemRows = items ?? [];
  const itemDetail: PurchaseOrderItemRow[] = itemRows.map((row) => {
    const it = row as unknown as {
      id: string;
      product_id: string;
      product_name: string | null;
      unit_id: string;
      unit_name: string | null;
      qty: number | string;
      qty_base: number | string;
      unit_price: number | string;
      line_total: number | string;
      note: string | null;
    };
    return mapPurchaseOrderItem(it);
  });

  return { ...main, note: r.note, items: itemDetail };
}

export type SupplierSelectOption = { id: string; name: string };

export async function getSupplierOptions(): Promise<SupplierSelectOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("suppliers")
    .select("id, name")
    .eq("tenant_id", base.tenantId)
    .eq("active", true)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
  }));
}

export type ProductSelectOption = { id: string; name: string; baseUnitId: string | null };

export async function getProductOptions(): Promise<ProductSelectOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("products")
    .select("id, name, base_unit_id")
    .eq("tenant_id", base.tenantId)
    .eq("active", true)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
    baseUnitId: row.base_unit_id,
  }));
}

export type UnitSelectOption = { id: string; name: string };

export async function getUnitOptions(): Promise<UnitSelectOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("units")
    .select("id, name")
    .eq("tenant_id", base.tenantId)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
  }));
}

export type OutletSelectOption = { id: string; name: string };

export async function getOutletOptions(): Promise<OutletSelectOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("outlets")
    .select("id, name")
    .eq("tenant_id", base.tenantId)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
  }));
}
