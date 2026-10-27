import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";
import type { Json } from "@/lib/supabase/types";

export type PaperWidth = "58" | "80";

export type ReceiptSettings = {
  storeName: string;
  address: string;
  phone: string;
  footer: string;
  logoUrl: string;
  paperWidth: PaperWidth;
  hideTaxPercent: boolean;
  showMechanic: boolean;
};

export function defaultReceiptSettings(storeName: string): ReceiptSettings {
  return {
    storeName,
    address: "",
    phone: "",
    footer: "",
    logoUrl: "",
    paperWidth: "58",
    hideTaxPercent: false,
    showMechanic: true,
  };
}

export function parseReceiptSettings(
  value: Json | undefined | null,
  storeName: string
): ReceiptSettings {
  const fallback = defaultReceiptSettings(storeName);
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return fallback;
  }

  const root = value as Record<string, unknown>;
  const receipt = root.receipt;
  if (
    typeof receipt !== "object" ||
    receipt === null ||
    Array.isArray(receipt)
  ) {
    return fallback;
  }

  const row = receipt as Record<string, unknown>;
  return {
    storeName:
      typeof row.storeName === "string" && row.storeName.trim() !== ""
        ? row.storeName
        : fallback.storeName,
    address: typeof row.address === "string" ? row.address : "",
    phone: typeof row.phone === "string" ? row.phone : "",
    footer: typeof row.footer === "string" ? row.footer : "",
    logoUrl: typeof row.logoUrl === "string" ? row.logoUrl : "",
    paperWidth: row.paperWidth === "80" ? "80" : "58",
    hideTaxPercent: row.hideTaxPercent === true,
    showMechanic: row.showMechanic !== false,
  };
}

export async function getReceiptSettingsForTenant(
  tenantId: string
): Promise<ReceiptSettings | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("tenants")
    .select("name, settings")
    .eq("id", tenantId)
    .maybeSingle();

  if (!data) return null;
  return parseReceiptSettings(data.settings, data.name);
}

export type ReceiptItem = {
  id: string;
  name: string;
  qty: number;
  unitName: string;
  unitPrice: number;
  discount: number;
  lineTotal: number;
  note: string | null;
};

export type ReceiptPayment = {
  id: string;
  method: string;
  amount: number;
  reference: string | null;
};

export type ReceiptData = {
  saleId: string;
  invoiceNo: string;
  soldAt: string;
  status: string;
  tenantName: string;
  outletName: string;
  customerName: string | null;
  customerPhone: string | null;
  note: string | null;
  items: ReceiptItem[];
  payments: ReceiptPayment[];
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  paidAmount: number;
  changeAmount: number;
  settings: ReceiptSettings;
};

export async function getReceipt(
  saleId: string
): Promise<ReceiptData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data: sale } = await supabase
    .from("sales")
    .select(
      "id, invoice_no, sold_at, status, subtotal, discount, tax, total, paid_amount, change_amount, customer_id, outlet_id, note"
    )
    .eq("tenant_id", base.tenantId)
    .eq("id", saleId)
    .maybeSingle();

  if (!sale) return null;

  const [itemsRes, paymentsRes, productsRes, unitsRes, outletRes, tenantRes] =
    await Promise.all([
      supabase
        .from("sale_items")
        .select(
          "id, product_id, unit_id, qty, unit_price, discount, line_total, note"
        )
        .eq("tenant_id", base.tenantId)
        .eq("sale_id", saleId)
        .order("created_at"),
      supabase
        .from("payments")
        .select("id, method, amount, reference")
        .eq("tenant_id", base.tenantId)
        .eq("sale_id", saleId),
      supabase
        .from("products")
        .select("id, name")
        .eq("tenant_id", base.tenantId),
      supabase.from("units").select("id, name").eq("tenant_id", base.tenantId),
      supabase
        .from("outlets")
        .select("name")
        .eq("tenant_id", base.tenantId)
        .eq("id", sale.outlet_id)
        .maybeSingle(),
      supabase
        .from("tenants")
        .select("name, settings")
        .eq("id", base.tenantId)
        .maybeSingle(),
    ]);

  const productNames = new Map(
    (productsRes.data ?? []).map((row) => [row.id, row.name])
  );
  const unitNames = new Map(
    (unitsRes.data ?? []).map((row) => [row.id, row.name])
  );

  let customerName: string | null = null;
  let customerPhone: string | null = null;
  if (sale.customer_id) {
    const { data: customer } = await supabase
      .from("customers")
      .select("name, phone")
      .eq("tenant_id", base.tenantId)
      .eq("id", sale.customer_id)
      .maybeSingle();
    customerName = customer?.name ?? null;
    customerPhone = customer?.phone ?? null;
  }

  const settings = parseReceiptSettings(
    tenantRes.data?.settings,
    tenantRes.data?.name ?? base.tenantName
  );

  return {
    saleId: sale.id,
    invoiceNo: sale.invoice_no,
    soldAt: sale.sold_at,
    status: sale.status,
    tenantName: tenantRes.data?.name ?? base.tenantName,
    outletName: outletRes.data?.name ?? "—",
    customerName,
    customerPhone,
    note: sale.note,
    items: (itemsRes.data ?? []).map((row) => ({
      id: row.id,
      name: productNames.get(row.product_id) ?? "—",
      qty: Number(row.qty),
      unitName: unitNames.get(row.unit_id) ?? "",
      unitPrice: Number(row.unit_price),
      discount: Number(row.discount),
      lineTotal: Number(row.line_total),
      note: row.note,
    })),
    payments: (paymentsRes.data ?? []).map((row) => ({
      id: row.id,
      method: row.method,
      amount: Number(row.amount),
      reference: row.reference,
    })),
    subtotal: Number(sale.subtotal),
    discount: Number(sale.discount),
    tax: Number(sale.tax),
    total: Number(sale.total),
    paidAmount: Number(sale.paid_amount),
    changeAmount: Number(sale.change_amount),
    settings,
  };
}

export type SaleListRow = {
  id: string;
  invoiceNo: string;
  soldAt: string;
  status: string;
  total: number;
  outletName: string;
  customerName: string | null;
};

export type SaleDetailItem = {
  id: string;
  name: string;
  qty: number;
  unitName: string;
  unitPrice: number;
  lineTotal: number;
  returnedQty: number;
  remainingQty: number;
  trackStock: boolean;
};

export type SaleReturnRow = {
  id: string;
  createdAt: string;
  reason: string;
  total: number;
  items: { id: string; name: string; qty: number; unitName: string }[];
};

export type SaleDetail = {
  id: string;
  invoiceNo: string;
  soldAt: string;
  status: string;
  invoiceTotal: number;
  paidAmount: number;
  outletName: string;
  customerName: string | null;
  note: string | null;
  voidReason: string | null;
  canManage: boolean;
  items: SaleDetailItem[];
  returns: SaleReturnRow[];
};

export async function getSaleDetail(
  saleId: string
): Promise<SaleDetail | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data: sale } = await supabase
    .from("sales")
    .select(
      "id, invoice_no, sold_at, status, total, paid_amount, outlet_id, customer_id, note, void_reason"
    )
    .eq("tenant_id", base.tenantId)
    .eq("id", saleId)
    .maybeSingle();

  if (!sale) return null;

  const [itemsRes, returnsRes, productsRes, unitsRes, outletRes] =
    await Promise.all([
      supabase
        .from("sale_items")
        .select("id, product_id, unit_id, qty, unit_price, line_total")
        .eq("tenant_id", base.tenantId)
        .eq("sale_id", saleId)
        .order("created_at"),
      supabase
        .from("sale_returns")
        .select("id, reason, total, created_at")
        .eq("tenant_id", base.tenantId)
        .eq("sale_id", saleId)
        .order("created_at", { ascending: false }),
      supabase
        .from("products")
        .select("id, name, track_stock")
        .eq("tenant_id", base.tenantId),
      supabase.from("units").select("id, name").eq("tenant_id", base.tenantId),
      supabase
        .from("outlets")
        .select("name")
        .eq("tenant_id", base.tenantId)
        .eq("id", sale.outlet_id)
        .maybeSingle(),
    ]);

  const returnIds = (returnsRes.data ?? []).map((row) => row.id);
  type ReturnItemRow = {
    id: string;
    return_id: string;
    sale_item_id: string;
    product_id: string;
    qty: number;
  };
  let returnItems: ReturnItemRow[] = [];
  if (returnIds.length > 0) {
    const { data } = await supabase
      .from("sale_return_items")
      .select("id, return_id, sale_item_id, product_id, qty")
      .eq("tenant_id", base.tenantId)
      .in("return_id", returnIds);
    returnItems = data ?? [];
  }

  const saleItemUnit = new Map(
    (itemsRes.data ?? []).map((row) => [row.id, row.unit_id])
  );

  const productNames = new Map(
    (productsRes.data ?? []).map((row) => [row.id, row.name])
  );
  const productTrack = new Map(
    (productsRes.data ?? []).map((row) => [row.id, row.track_stock])
  );
  const unitNames = new Map(
    (unitsRes.data ?? []).map((row) => [row.id, row.name])
  );

  const returnedByItem = new Map<string, number>();
  for (const row of returnItems ?? []) {
    returnedByItem.set(
      row.sale_item_id,
      (returnedByItem.get(row.sale_item_id) ?? 0) + Number(row.qty)
    );
  }

  let customerName: string | null = null;
  if (sale.customer_id) {
    const { data: customer } = await supabase
      .from("customers")
      .select("name")
      .eq("tenant_id", base.tenantId)
      .eq("id", sale.customer_id)
      .maybeSingle();
    customerName = customer?.name ?? null;
  }

  const items: SaleDetailItem[] = (itemsRes.data ?? []).map((row) => {
    const returnedQty = returnedByItem.get(row.id) ?? 0;
    return {
      id: row.id,
      name: productNames.get(row.product_id) ?? "—",
      qty: Number(row.qty),
      unitName: unitNames.get(row.unit_id) ?? "",
      unitPrice: Number(row.unit_price),
      lineTotal: Number(row.line_total),
      returnedQty,
      remainingQty: Math.max(0, Number(row.qty) - returnedQty),
      trackStock: productTrack.get(row.product_id) ?? false,
    };
  });

  const returns: SaleReturnRow[] = (returnsRes.data ?? []).map((row) => ({
    id: row.id,
    createdAt: row.created_at,
    reason: row.reason,
    total: Number(row.total),
    items: (returnItems ?? [])
      .filter((item) => item.return_id === row.id)
      .map((item) => ({
        id: item.id,
        name: productNames.get(item.product_id) ?? "—",
        qty: Number(item.qty),
        unitName: unitNames.get(saleItemUnit.get(item.sale_item_id) ?? "") ?? "",
      })),
  }));

  return {
    id: sale.id,
    invoiceNo: sale.invoice_no,
    soldAt: sale.sold_at,
    status: sale.status,
    invoiceTotal: Number(sale.total),
    paidAmount: Number(sale.paid_amount),
    outletName: outletRes.data?.name ?? "—",
    customerName,
    note: sale.note,
    voidReason: sale.void_reason,
    canManage: ["owner", "admin"].includes(base.role),
    items,
    returns,
  };
}

export async function getRecentSales(limit = 50): Promise<{
  tenantName: string;
  rows: SaleListRow[];
} | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("sales")
    .select(
      "id, invoice_no, sold_at, status, total, customer_id, outlet_id"
    )
    .eq("tenant_id", base.tenantId)
    .order("sold_at", { ascending: false })
    .limit(limit);

  const [outletsRes, customersRes] = await Promise.all([
    supabase
      .from("outlets")
      .select("id, name")
      .eq("tenant_id", base.tenantId),
    supabase
      .from("customers")
      .select("id, name")
      .eq("tenant_id", base.tenantId),
  ]);

  const outletNames = new Map(
    (outletsRes.data ?? []).map((row) => [row.id, row.name])
  );
  const customerNames = new Map(
    (customersRes.data ?? []).map((row) => [row.id, row.name])
  );

  return {
    tenantName: base.tenantName,
    rows: (data ?? []).map((row) => ({
      id: row.id,
      invoiceNo: row.invoice_no,
      soldAt: row.sold_at,
      status: row.status,
      total: Number(row.total),
      outletName: outletNames.get(row.outlet_id) ?? "—",
      customerName: row.customer_id
        ? customerNames.get(row.customer_id) ?? null
        : null,
    })),
  };
}
