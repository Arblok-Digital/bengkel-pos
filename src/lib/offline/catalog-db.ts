import Dexie, { type Table } from "dexie";

import type {
  CachedCustomer,
  CachedPriceBreak,
  CachedProduct,
  CachedProductUnit,
  CachedStockLevel,
  CatalogMeta,
} from "./catalog-schema";

export const CATALOG_DB_NAME = "bengkel-pos";

export class OfflineCatalogDb extends Dexie {
  meta!: Table<CatalogMeta, string>;
  products!: Table<CachedProduct, [string, string]>;
  productUnits!: Table<CachedProductUnit, [string, string, string]>;
  priceBreaks!: Table<CachedPriceBreak, [string, string, string, number]>;
  stockLevels!: Table<CachedStockLevel, [string, string]>;
  customers!: Table<CachedCustomer, [string, string]>;

  constructor(name: string = CATALOG_DB_NAME) {
    super(name);
    this.version(1).stores({
      meta: "scopeKey, tenantId, lastSyncedAt",
      products: "[scopeKey+id], scopeKey, tenantId, name",
      productUnits:
        "[scopeKey+productId+unitId], scopeKey, productId, tenantId",
      priceBreaks:
        "[scopeKey+productId+unitId+minQty], scopeKey, productId, tenantId",
      stockLevels: "[scopeKey+productId], scopeKey, tenantId, outletId",
      customers: "[tenantId+id], tenantId, name",
    });
  }
}

export function createCatalogDb(name: string = CATALOG_DB_NAME): OfflineCatalogDb {
  return new OfflineCatalogDb(name);
}

let defaultDb: OfflineCatalogDb | null = null;

/**
 * Instance untuk browser. Dibuat malas supaya modul ini tetap aman
 * diimpor saat render server (Dexie baru menyentuh IndexedDB saat dipakai).
 */
export function getCatalogDb(): OfflineCatalogDb {
  defaultDb ??= createCatalogDb();
  return defaultDb;
}
