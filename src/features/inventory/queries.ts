import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";

export type StockRow = {
  outletId: string;
  outletName: string;
  productId: string;
  productName: string;
  sku: string | null;
  qtyBase: number;
  minStock: number;
  isLow: boolean;
};

export type StockPageData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  rows: StockRow[];
};

export async function getStockByOutlet(): Promise<StockPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("stock_by_outlet")
    .select(
      "outlet_id, outlet_name, product_id, product_name, sku, qty_base, min_stock, is_low"
    )
    .eq("tenant_id", base.tenantId)
    .order("product_name");

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    rows: (data ?? []).map((row) => ({
      outletId: row.outlet_id ?? "",
      outletName: row.outlet_name ?? "—",
      productId: row.product_id ?? "",
      productName: row.product_name ?? "—",
      sku: row.sku,
      qtyBase: Number(row.qty_base ?? 0),
      minStock: Number(row.min_stock ?? 0),
      isLow: Boolean(row.is_low),
    })),
  };
}

export type LowStockRow = {
  outletName: string;
  productId: string;
  productName: string;
  sku: string | null;
  qtyBase: number;
  minStock: number;
  shortage: number;
};

export type LowStockData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  rows: LowStockRow[];
};

/** Produk dengan stok di bawah min_stock, paling parah lebih dulu. */
export async function getLowStock(): Promise<LowStockData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("stock_by_outlet")
    .select(
      "outlet_name, product_id, product_name, sku, qty_base, min_stock, is_low"
    )
    .eq("tenant_id", base.tenantId)
    .eq("is_low", true);

  const rows: LowStockRow[] = (data ?? []).map((row) => ({
    outletName: row.outlet_name ?? "—",
    productId: row.product_id ?? "",
    productName: row.product_name ?? "—",
    sku: row.sku,
    qtyBase: Number(row.qty_base ?? 0),
    minStock: Number(row.min_stock ?? 0),
    shortage: Number(row.min_stock ?? 0) - Number(row.qty_base ?? 0),
  }));

  rows.sort(
    (a, b) =>
      b.shortage - a.shortage || a.productName.localeCompare(b.productName)
  );

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    rows,
  };
}

export type StockAdjustmentData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  products: { id: string; name: string }[];
  outlets: { id: string; name: string }[];
};

export async function getStockAdjustmentData(): Promise<StockAdjustmentData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const [productsRes, outletsRes] = await Promise.all([
    supabase
      .from("products")
      .select("id, name")
      .eq("tenant_id", base.tenantId)
      .eq("track_stock", true)
      .eq("active", true)
      .order("name"),
    supabase
      .from("outlets")
      .select("id, name")
      .eq("tenant_id", base.tenantId)
      .order("name"),
  ]);

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    products: productsRes.data ?? [],
    outlets: outletsRes.data ?? [],
  };
}

export type StockCardRow = {
  id: string;
  outletName: string;
  qtyBase: number;
  type: string;
  note: string | null;
  createdAt: string;
};

export type StockCardData = {
  tenantName: string;
  productName: string;
  sku: string | null;
  minStock: number;
  rows: StockCardRow[];
};

export async function getStockCard(
  productId: string
): Promise<StockCardData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const [productRes, movementsRes, outletsRes] = await Promise.all([
    supabase
      .from("products")
      .select("id, name, sku, min_stock")
      .eq("tenant_id", base.tenantId)
      .eq("id", productId)
      .maybeSingle(),
    supabase
      .from("stock_movements")
      .select("id, outlet_id, qty_base, type, note, created_at")
      .eq("tenant_id", base.tenantId)
      .eq("product_id", productId)
      .order("created_at", { ascending: false }),
    supabase
      .from("outlets")
      .select("id, name")
      .eq("tenant_id", base.tenantId),
  ]);

  if (!productRes.data) return null;

  const outletNames = new Map(
    (outletsRes.data ?? []).map((outlet) => [outlet.id, outlet.name])
  );

  return {
    tenantName: base.tenantName,
    productName: productRes.data.name,
    sku: productRes.data.sku,
    minStock: Number(productRes.data.min_stock),
    rows: (movementsRes.data ?? []).map((row) => ({
      id: row.id,
      outletName: outletNames.get(row.outlet_id) ?? "—",
      qtyBase: Number(row.qty_base),
      type: row.type,
      note: row.note,
      createdAt: row.created_at,
    })),
  };
}

export type OpnameListRow = {
  id: string;
  outletName: string;
  status: string;
  note: string | null;
  createdAt: string;
};

export type OpnamesPageData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  outlets: { id: string; name: string }[];
  opnames: OpnameListRow[];
};

export async function getOpnamesPage(): Promise<OpnamesPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const [outletsRes, opnamesRes] = await Promise.all([
    supabase
      .from("outlets")
      .select("id, name")
      .eq("tenant_id", base.tenantId)
      .order("name"),
    supabase
      .from("stock_opnames")
      .select("id, outlet_id, status, note, created_at")
      .eq("tenant_id", base.tenantId)
      .order("created_at", { ascending: false }),
  ]);

  const outletNames = new Map(
    (outletsRes.data ?? []).map((outlet) => [outlet.id, outlet.name])
  );

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    outlets: outletsRes.data ?? [],
    opnames: (opnamesRes.data ?? []).map((row) => ({
      id: row.id,
      outletName: outletNames.get(row.outlet_id) ?? "—",
      status: row.status,
      note: row.note,
      createdAt: row.created_at,
    })),
  };
}

export type OpnameItemRow = {
  id: string;
  productName: string;
  systemQty: number;
  countedQty: number | null;
  difference: number;
};

export type OpnameDetailData = {
  id: string;
  tenantId: string;
  tenantName: string;
  outletName: string;
  status: string;
  note: string | null;
  canWrite: boolean;
  items: OpnameItemRow[];
};

export async function getOpnameDetail(
  opnameId: string
): Promise<OpnameDetailData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const [opnameRes, itemsRes] = await Promise.all([
    supabase
      .from("stock_opnames")
      .select("id, tenant_id, outlet_id, status, note")
      .eq("tenant_id", base.tenantId)
      .eq("id", opnameId)
      .maybeSingle(),
    supabase
      .from("stock_opname_items")
      .select("id, product_id, system_qty, counted_qty, difference")
      .eq("tenant_id", base.tenantId)
      .eq("opname_id", opnameId)
      .order("product_id"),
  ]);

  if (!opnameRes.data) return null;

  const [outletRes, productsRes] = await Promise.all([
    supabase
      .from("outlets")
      .select("name")
      .eq("tenant_id", base.tenantId)
      .eq("id", opnameRes.data.outlet_id)
      .maybeSingle(),
    supabase
      .from("products")
      .select("id, name")
      .eq("tenant_id", base.tenantId),
  ]);

  const productNames = new Map(
    (productsRes.data ?? []).map((product) => [product.id, product.name])
  );

  return {
    id: opnameRes.data.id,
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    outletName: outletRes.data?.name ?? "—",
    status: opnameRes.data.status,
    note: opnameRes.data.note,
    canWrite: base.canWrite,
    items: (itemsRes.data ?? []).map((row) => ({
      id: row.id,
      productName: productNames.get(row.product_id) ?? "—",
      systemQty: Number(row.system_qty),
      countedQty: row.counted_qty === null ? null : Number(row.counted_qty),
      difference: Number(row.difference),
    })),
  };
}
