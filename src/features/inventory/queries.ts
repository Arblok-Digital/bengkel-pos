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
