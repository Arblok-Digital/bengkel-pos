// Skema cache katalog offline (Dexie).
//
// Aturan:
// - Semua baris produk/stok/satuan diberi `scopeKey` = tenant + outlet + tier.
// - Pelanggan bersifat per tenant (bukan per outlet), tetap memakai tenantId.
// - Tidak ada cost_price/unit_cost/HPP di sini. Hanya harga jual dari
//   pos_catalog + price_breaks (keduanya harga jual).

export const CACHE_SCHEMA_VERSION = 1;

export type CatalogScope = {
  tenantId: string;
  outletId: string;
  tierId: string | null;
};

export type CatalogMeta = CatalogScope & {
  scopeKey: string;
  schemaVersion: number;
  lastSyncedAt: string;
  payloadHash: string;
  productCount: number;
  customerCount: number;
};

export type CachedProduct = {
  scopeKey: string;
  tenantId: string;
  outletId: string;
  tierId: string | null;
  id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  baseUnitId: string;
  baseUnitName: string;
  price: number;
  trackStock: boolean;
};

export type CachedProductUnit = {
  scopeKey: string;
  tenantId: string;
  productId: string;
  unitId: string;
  name: string;
  factor: number;
  price: number;
  isBase: boolean;
};

export type CachedPriceBreak = {
  scopeKey: string;
  tenantId: string;
  productId: string;
  unitId: string;
  minQty: number;
  price: number;
};

export type CachedStockLevel = {
  scopeKey: string;
  tenantId: string;
  outletId: string;
  productId: string;
  qtyBase: number;
  minStock: number;
  isLow: boolean;
  syncedAt: string;
};

export type CachedCustomer = {
  tenantId: string;
  id: string;
  name: string;
  tierId: string | null;
  creditLimit: number;
};

export type CachedPriceBreakInput = {
  productId: string;
  unitId: string;
  minQty: number;
  price: number;
};

/** Kunci scope. UUID tidak mengandung "::", jadi aman sebagai pemisah. */
export function buildScopeKey(scope: CatalogScope): string {
  return `${scope.tenantId}::${scope.outletId}::${
    scope.tierId ?? "tanpa-tier"
  }`;
}

export function normalizeScope(scope: CatalogScope): CatalogScope {
  return {
    tenantId: scope.tenantId,
    outletId: scope.outletId,
    tierId: scope.tierId || null,
  };
}

/** Cache dari versi skema lain harus dianggap kosong (hidrasi ulang). */
export function isSnapshotCompatible(
  meta: Pick<CatalogMeta, "schemaVersion"> | undefined,
  version: number = CACHE_SCHEMA_VERSION
): boolean {
  return Boolean(meta && meta.schemaVersion === version);
}

function fnv1a(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

type HashProduct = {
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
  units: { unitId: string; name: string; factor: number; price: number }[];
};

type HashCustomer = {
  id: string;
  name: string;
  tierId: string | null;
  creditLimit: number;
};

/** Hash isi snapshot; dipakai untuk metadata sinkron (bukan keamanan). */
export function buildSnapshotHash(input: {
  products: readonly HashProduct[];
  customers: readonly HashCustomer[];
  priceBreaks: readonly CachedPriceBreakInput[];
}): string {
  const products = [...input.products]
    .sort((a, b) => a.id.localeCompare(b.id))
    .map((product) =>
      [
        product.id,
        product.name,
        product.sku ?? "",
        product.barcode ?? "",
        product.baseUnitId,
        product.baseUnitName,
        product.price,
        product.stockQty,
        product.minStock,
        product.isLow ? 1 : 0,
        product.trackStock ? 1 : 0,
        [...product.units]
          .sort((a, b) => a.unitId.localeCompare(b.unitId))
          .map((unit) => [unit.unitId, unit.name, unit.factor, unit.price].join(":"))
          .join(","),
      ].join("~")
    );

  const customers = [...input.customers]
    .sort((a, b) => a.id.localeCompare(b.id))
    .map((customer) =>
      [customer.id, customer.name, customer.tierId ?? "", customer.creditLimit].join(
        "~"
      )
    );

  const breaks = [...input.priceBreaks]
    .sort(
      (a, b) =>
        a.productId.localeCompare(b.productId) ||
        a.unitId.localeCompare(b.unitId) ||
        a.minQty - b.minQty
    )
    .map((row) =>
      [row.productId, row.unitId, row.minQty, row.price].join("~")
    );

  return fnv1a([products.join("|"), customers.join("|"), breaks.join("|")].join("#"));
}
