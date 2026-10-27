import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";
import type { Json } from "@/lib/supabase/types";

export type PosUnit = {
  unitId: string;
  name: string;
  factor: number;
  price: number;
};

export type PosProduct = {
  id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  baseUnitId: string;
  baseUnitName: string;
  price: number;
  stockQty: number;
  minStock: number;
  isLow: boolean;
  trackStock: boolean;
  units: PosUnit[];
};

export type PosCustomer = {
  id: string;
  name: string;
  tierId: string | null;
  creditLimit: number;
};

/** Harga grosir per satuan (harga jual, bukan HPP). */
export type PosPriceBreak = {
  productId: string;
  unitId: string;
  minQty: number;
  price: number;
};

export type PosShift = {
  id: string;
  outletId: string;
  outletName: string;
  openedAt: string;
  openingCash: number;
};

export type PosData = {
  tenantId: string;
  tenantName: string;
  canSell: boolean;
  defaultTierId: string | null;
  shift: PosShift | null;
  customers: PosCustomer[];
  products: PosProduct[];
};

type PosCatalogRow = {
  product_id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  base_unit_id: string;
  base_unit_name: string | null;
  price: number;
  stock_qty: number;
  min_stock: number;
  is_low: boolean;
  track_stock: boolean;
  units: Json;
};

function toUnits(value: Json): PosUnit[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (typeof item !== "object" || item === null || Array.isArray(item)) {
      return [];
    }
    const row = item as Record<string, unknown>;
    return [
      {
        unitId: String(row.unit_id ?? ""),
        name: String(row.name ?? ""),
        factor: Number(row.factor ?? 1),
        price: Number(row.price ?? 0),
      },
    ];
  });
}

function toProduct(row: PosCatalogRow): PosProduct {
  return {
    id: row.product_id,
    name: row.name,
    sku: row.sku,
    barcode: row.barcode,
    baseUnitId: row.base_unit_id,
    baseUnitName: row.base_unit_name ?? "—",
    price: Number(row.price ?? 0),
    stockQty: Number(row.stock_qty ?? 0),
    minStock: Number(row.min_stock ?? 0),
    isLow: Boolean(row.is_low),
    trackStock: Boolean(row.track_stock),
    units: toUnits(row.units),
  };
}

export async function getPosProducts(
  tenantId: string,
  outletId: string,
  tierId: string | null
): Promise<PosProduct[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("pos_catalog", {
    p_tenant_id: tenantId,
    p_outlet_id: outletId,
    p_tier_id: tierId,
  });

  if (error || !data) return [];
  return (data as PosCatalogRow[]).map(toProduct);
}

/** Shift terbuka milik user + tenant aktif (tanpa memuat katalog). */
export async function getPosShift(): Promise<{
  tenantId: string;
  tenantName: string;
  shift: PosShift | null;
} | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const shiftRes = await supabase
    .from("cash_shifts")
    .select("id, outlet_id, opened_at, opening_cash")
    .eq("tenant_id", base.tenantId)
    .eq("cashier_id", user.id)
    .is("closed_at", null)
    .order("opened_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!shiftRes.data) {
    return { tenantId: base.tenantId, tenantName: base.tenantName, shift: null };
  }

  const outletRes = await supabase
    .from("outlets")
    .select("name")
    .eq("tenant_id", base.tenantId)
    .eq("id", shiftRes.data.outlet_id)
    .maybeSingle();

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    shift: {
      id: shiftRes.data.id,
      outletId: shiftRes.data.outlet_id,
      outletName: outletRes.data?.name ?? "—",
      openedAt: shiftRes.data.opened_at,
      openingCash: Number(shiftRes.data.opening_cash),
    },
  };
}

/** Pelanggan aktif tenant untuk layar kasir + cache offline. */
export async function getPosCustomers(tenantId: string): Promise<PosCustomer[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("customers")
    .select("id, name, tier_id, credit_limit")
    .eq("tenant_id", tenantId)
    .eq("active", true)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
    tierId: row.tier_id,
    creditLimit: Number(row.credit_limit ?? 0),
  }));
}

/** Harga grosir tenant untuk cache offline. Tidak memuat HPP. */
export async function getPosPriceBreaks(
  tenantId: string
): Promise<PosPriceBreak[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("price_breaks")
    .select("product_id, unit_id, min_qty, price")
    .eq("tenant_id", tenantId);

  return (data ?? []).map((row) => ({
    productId: row.product_id,
    unitId: row.unit_id,
    minQty: Number(row.min_qty),
    price: row.price,
  }));
}

/** Katalog + shift terbuka + pelanggan untuk layar kasir. */
export async function getPosData(): Promise<PosData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [context, customers, tierRes] = await Promise.all([
    getPosShift(),
    getPosCustomers(base.tenantId),
    supabase
      .from("price_tiers")
      .select("id")
      .eq("tenant_id", base.tenantId)
      .eq("name", "Umum")
      .maybeSingle(),
  ]);

  if (!context) return null;

  if (!context.shift) {
    return {
      tenantId: base.tenantId,
      tenantName: base.tenantName,
      canSell: ["owner", "admin", "kasir"].includes(base.role),
      defaultTierId: tierRes.data?.id ?? null,
      shift: null,
      customers,
      products: [],
    };
  }

  const products = await getPosProducts(
    base.tenantId,
    context.shift.outletId,
    tierRes.data?.id ?? null
  );

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canSell: ["owner", "admin", "kasir"].includes(base.role),
    defaultTierId: tierRes.data?.id ?? null,
    shift: context.shift,
    customers,
    products,
  };
}
