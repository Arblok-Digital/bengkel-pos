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
