import type {
  PosCustomer,
  PosPriceBreak,
  PosProduct,
  PosUnit,
} from "@/features/pos/queries";
import { addQtyDecimal } from "@/lib/qty";

import type { OfflineCatalogDb } from "./catalog-db";
import { searchProducts } from "./catalog-search";
import {
  buildScopeKey,
  buildSnapshotHash,
  CACHE_SCHEMA_VERSION,
  isSnapshotCompatible,
  normalizeScope,
  type CachedCustomer,
  type CachedPriceBreak,
  type CachedProduct,
  type CachedProductUnit,
  type CachedStockLevel,
  type CatalogMeta,
  type CatalogScope,
} from "./catalog-schema";

export type CatalogSnapshot = {
  products: PosProduct[];
  customers: PosCustomer[];
  priceBreaks: PosPriceBreak[];
};

export type CatalogRead = {
  products: PosProduct[];
  customers: PosCustomer[];
  priceBreaks: PosPriceBreak[];
  meta: CatalogMeta;
};

const ALL_TABLES = (db: OfflineCatalogDb) => [
  db.meta,
  db.products,
  db.productUnits,
  db.priceBreaks,
  db.stockLevels,
  db.customers,
];

function baseUnits(product: PosProduct): PosUnit[] {
  const units = [...product.units].sort(
    (a, b) => a.factor - b.factor || a.name.localeCompare(b.name, "id")
  );
  if (units.length > 0) return units;

  // pos_catalog selalu mengirim satuan dasar, tetapi cache harus tetap bisa
  // dipakai kalau data lama/terpotong.
  return [
    {
      unitId: product.baseUnitId,
      name: product.baseUnitName,
      factor: 1,
      price: product.price,
    },
  ];
}

function toProductRecord(
  scope: CatalogScope,
  scopeKey: string,
  product: PosProduct
): CachedProduct {
  return {
    scopeKey,
    tenantId: scope.tenantId,
    outletId: scope.outletId,
    tierId: scope.tierId,
    id: product.id,
    name: product.name,
    sku: product.sku,
    barcode: product.barcode,
    baseUnitId: product.baseUnitId,
    baseUnitName: product.baseUnitName,
    price: product.price,
    trackStock: product.trackStock,
  };
}

function toUnitRecords(
  scope: CatalogScope,
  scopeKey: string,
  product: PosProduct
): CachedProductUnit[] {
  return baseUnits(product).map((unit) => ({
    scopeKey,
    tenantId: scope.tenantId,
    productId: product.id,
    unitId: unit.unitId,
    name: unit.name,
    factor: unit.factor,
    price: unit.price,
    isBase: unit.unitId === product.baseUnitId,
  }));
}

function toStockRecord(
  scope: CatalogScope,
  scopeKey: string,
  product: PosProduct,
  syncedAt: string
): CachedStockLevel {
  return {
    scopeKey,
    tenantId: scope.tenantId,
    outletId: scope.outletId,
    productId: product.id,
    qtyBase: product.stockQty,
    minStock: product.minStock,
    isLow: product.isLow,
    syncedAt,
  };
}

function toPriceBreakRecords(
  scope: CatalogScope,
  scopeKey: string,
  productIds: Set<string>,
  breaks: readonly PosPriceBreak[]
): CachedPriceBreak[] {
  return breaks
    .filter((row) => productIds.has(row.productId))
    .map((row) => ({
      scopeKey,
      tenantId: scope.tenantId,
      productId: row.productId,
      unitId: row.unitId,
      minQty: row.minQty,
      price: row.price,
    }));
}

function toCustomerRecords(
  tenantId: string,
  customers: readonly PosCustomer[]
): CachedCustomer[] {
  return customers.map((customer) => ({
    tenantId,
    id: customer.id,
    name: customer.name,
    tierId: customer.tierId,
    creditLimit: customer.creditLimit,
  }));
}

/**
 * Simpan snapshot untuk satu scope. Data tenant lain dihapus supaya perangkat
 * yang dipakai bergantian tidak menyimpan katalog tenant sebelumnya.
 */
export async function hydrateCatalog(
  db: OfflineCatalogDb,
  scopeInput: CatalogScope,
  snapshot: CatalogSnapshot,
  now: Date = new Date()
): Promise<CatalogMeta> {
  const scope = normalizeScope(scopeInput);
  const scopeKey = buildScopeKey(scope);
  const syncedAt = now.toISOString();
  const productIds = new Set(snapshot.products.map((product) => product.id));

  const meta: CatalogMeta = {
    ...scope,
    scopeKey,
    schemaVersion: CACHE_SCHEMA_VERSION,
    lastSyncedAt: syncedAt,
    payloadHash: buildSnapshotHash(snapshot),
    productCount: snapshot.products.length,
    customerCount: snapshot.customers.length,
  };

  const products = snapshot.products.map((product) =>
    toProductRecord(scope, scopeKey, product)
  );
  const units = snapshot.products.flatMap((product) =>
    toUnitRecords(scope, scopeKey, product)
  );
  const stock = snapshot.products.map((product) =>
    toStockRecord(scope, scopeKey, product, syncedAt)
  );
  const breaks = toPriceBreakRecords(
    scope,
    scopeKey,
    productIds,
    snapshot.priceBreaks
  );
  const customers = toCustomerRecords(scope.tenantId, snapshot.customers);

  await db.transaction("rw", ALL_TABLES(db), async () => {
    await db.meta.where("tenantId").notEqual(scope.tenantId).delete();
    await db.products.where("tenantId").notEqual(scope.tenantId).delete();
    await db.productUnits.where("tenantId").notEqual(scope.tenantId).delete();
    await db.priceBreaks.where("tenantId").notEqual(scope.tenantId).delete();
    await db.stockLevels.where("tenantId").notEqual(scope.tenantId).delete();
    await db.customers.where("tenantId").notEqual(scope.tenantId).delete();

    await db.products.where("scopeKey").equals(scopeKey).delete();
    await db.productUnits.where("scopeKey").equals(scopeKey).delete();
    await db.priceBreaks.where("scopeKey").equals(scopeKey).delete();
    await db.stockLevels.where("scopeKey").equals(scopeKey).delete();
    await db.customers.where("tenantId").equals(scope.tenantId).delete();

    await db.products.bulkPut(products);
    await db.productUnits.bulkPut(units);
    await db.priceBreaks.bulkPut(breaks);
    await db.stockLevels.bulkPut(stock);
    await db.customers.bulkPut(customers);
    await db.meta.put(meta);
  });

  return meta;
}

async function clearScopeRows(
  db: OfflineCatalogDb,
  scope: CatalogScope
): Promise<void> {
  const scopeKey = buildScopeKey(scope);
  await db.transaction("rw", ALL_TABLES(db), async () => {
    await db.products.where("scopeKey").equals(scopeKey).delete();
    await db.productUnits.where("scopeKey").equals(scopeKey).delete();
    await db.priceBreaks.where("scopeKey").equals(scopeKey).delete();
    await db.stockLevels.where("scopeKey").equals(scopeKey).delete();
    await db.customers.where("tenantId").equals(scope.tenantId).delete();
    await db.meta.delete(scopeKey);
  });
}

function toPosProducts(
  products: CachedProduct[],
  units: CachedProductUnit[],
  stock: CachedStockLevel[]
): PosProduct[] {
  const unitsByProduct = new Map<string, CachedProductUnit[]>();
  for (const unit of units) {
    const rows = unitsByProduct.get(unit.productId) ?? [];
    rows.push(unit);
    unitsByProduct.set(unit.productId, rows);
  }

  const stockByProduct = new Map(stock.map((row) => [row.productId, row]));

  return [...products]
    .sort((a, b) => a.name.localeCompare(b.name, "id"))
    .map((product) => {
      const productUnits = [...(unitsByProduct.get(product.id) ?? [])].sort(
        (a, b) => a.factor - b.factor || a.name.localeCompare(b.name, "id")
      );
      const stockRow = stockByProduct.get(product.id);

      return {
        id: product.id,
        name: product.name,
        sku: product.sku,
        barcode: product.barcode,
        baseUnitId: product.baseUnitId,
        baseUnitName: product.baseUnitName,
        price: product.price,
        stockQty: stockRow?.qtyBase ?? 0,
        minStock: stockRow?.minStock ?? 0,
        isLow: stockRow?.isLow ?? false,
        trackStock: product.trackStock,
        units: productUnits.map((unit) => ({
          unitId: unit.unitId,
          name: unit.name,
          factor: unit.factor,
          price: unit.price,
        })),
      };
    });
}

/** Baca snapshot scope. Null kalau belum ada atau versi skema tidak cocok. */
export async function readCatalog(
  db: OfflineCatalogDb,
  scopeInput: CatalogScope
): Promise<CatalogRead | null> {
  const scope = normalizeScope(scopeInput);
  const scopeKey = buildScopeKey(scope);
  const meta = await db.meta.get(scopeKey);

  if (!meta) return null;
  if (!isSnapshotCompatible(meta)) {
    await clearScopeRows(db, scope);
    return null;
  }

  const [products, units, breaks, stock, customers] = await Promise.all([
    db.products.where("scopeKey").equals(scopeKey).toArray(),
    db.productUnits.where("scopeKey").equals(scopeKey).toArray(),
    db.priceBreaks.where("scopeKey").equals(scopeKey).toArray(),
    db.stockLevels.where("scopeKey").equals(scopeKey).toArray(),
    db.customers.where("tenantId").equals(scope.tenantId).toArray(),
  ]);

  return {
    products: toPosProducts(products, units, stock),
    customers: [...customers]
      .sort((a, b) => a.name.localeCompare(b.name, "id"))
      .map((customer) => ({
        id: customer.id,
        name: customer.name,
        tierId: customer.tierId,
        creditLimit: customer.creditLimit,
      })),
    priceBreaks: breaks.map((row) => ({
      productId: row.productId,
      unitId: row.unitId,
      minQty: row.minQty,
      price: row.price,
    })),
    meta,
  };
}

export type CachedSaleLine = {
  productId: string;
  qtyBase: number;
};

/**
 * Kurangi stok di cache lokal untuk transaksi offline. Ini hanya cermin layar
 * kasir, bukan sumber kebenaran: stok server tetap dipotong oleh create_sale /
 * resolve_sale_review. Tanpa ini kasir bisa menjual barang yang sama berulang
 * kali saat offline dan semuanya berakhir needs_review.
 */
export async function applyCachedSale(
  db: OfflineCatalogDb,
  scopeInput: CatalogScope,
  lines: readonly CachedSaleLine[]
): Promise<void> {
  const scope = normalizeScope(scopeInput);
  const scopeKey = buildScopeKey(scope);

  await db.transaction("rw", [db.stockLevels, db.products], async () => {
    for (const line of lines) {
      const stock = await db.stockLevels.get([scopeKey, line.productId]);
      if (!stock) continue;

      const product = await db.products.get([scopeKey, line.productId]);
      const qtyBase = Math.max(0, addQtyDecimal(stock.qtyBase, -line.qtyBase));

      await db.stockLevels.put({
        ...stock,
        qtyBase,
        isLow:
          Boolean(product?.trackStock) &&
          stock.minStock > 0 &&
          qtyBase < stock.minStock,
      });
    }
  });
}

/** Pencarian instan dari tabel produk Dexie (nama, SKU, barcode). */
export async function searchCachedProducts(
  db: OfflineCatalogDb,
  scope: CatalogScope,
  query: string
): Promise<PosProduct[]> {
  const read = await readCatalog(db, scope);
  if (!read) return [];
  return searchProducts(read.products, query);
}

/** Hapus seluruh cache. Dipakai saat logout. */
export async function clearOfflineCatalog(
  db: OfflineCatalogDb
): Promise<void> {
  await db.transaction("rw", ALL_TABLES(db), async () => {
    await Promise.all([
      db.meta.clear(),
      db.products.clear(),
      db.productUnits.clear(),
      db.priceBreaks.clear(),
      db.stockLevels.clear(),
      db.customers.clear(),
    ]);
  });
}
