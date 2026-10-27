import "fake-indexeddb/auto";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { PosCustomer, PosProduct } from "@/features/pos/queries";

import { createCatalogDb, type OfflineCatalogDb } from "./catalog-db";
import { buildScopeKey, type CatalogScope } from "./catalog-schema";
import {
  applyCachedSale,
  clearOfflineCatalog,
  hydrateCatalog,
  readCatalog,
  searchCachedProducts,
  type CatalogSnapshot,
} from "./catalog-store";

const scopeA: CatalogScope = {
  tenantId: "tenant-a",
  outletId: "outlet-1",
  tierId: "tier-umum",
};

const scopeB: CatalogScope = {
  tenantId: "tenant-b",
  outletId: "outlet-1",
  tierId: "tier-umum",
};

function makeProduct(overrides: Partial<PosProduct> = {}): PosProduct {
  return {
    id: "produk-oli",
    name: "Oli Mesin 1L",
    sku: "OLI-1L",
    barcode: "8999001",
    baseUnitId: "unit-liter",
    baseUnitName: "liter",
    price: 55000,
    stockQty: 7,
    minStock: 2,
    isLow: false,
    trackStock: true,
    units: [
      { unitId: "unit-liter", name: "liter", factor: 1, price: 55000 },
      { unitId: "unit-dus", name: "dus", factor: 12, price: 600000 },
    ],
    ...overrides,
  };
}

function makeCustomer(overrides: Partial<PosCustomer> = {}): PosCustomer {
  return {
    id: "pelanggan-budi",
    name: "Budi",
    tierId: "tier-umum",
    creditLimit: 0,
    ...overrides,
  };
}

function makeSnapshot(overrides: Partial<CatalogSnapshot> = {}): CatalogSnapshot {
  return {
    products: [
      makeProduct(),
      makeProduct({
        id: "produk-semen",
        name: "Semen 40kg",
        sku: "SEMEN-1",
        barcode: "8999002",
        baseUnitId: "unit-sak",
        baseUnitName: "sak",
        price: 65000,
        stockQty: 2,
        minStock: 5,
        isLow: true,
        units: [{ unitId: "unit-sak", name: "sak", factor: 1, price: 65000 }],
      }),
    ],
    customers: [makeCustomer()],
    priceBreaks: [
      {
        productId: "produk-oli",
        unitId: "unit-dus",
        minQty: 2,
        price: 590000,
      },
    ],
    ...overrides,
  };
}

let db: OfflineCatalogDb;

beforeEach(() => {
  db = createCatalogDb(`bengkel-pos-test-${crypto.randomUUID()}`);
});

afterEach(async () => {
  await db.delete();
});

describe("hydrateCatalog + readCatalog", () => {
  it("menyimpan produk, satuan, stok, harga grosir, dan pelanggan", async () => {
    const meta = await hydrateCatalog(db, scopeA, makeSnapshot());
    expect(meta.scopeKey).toBe(buildScopeKey(scopeA));
    expect(meta.productCount).toBe(2);
    expect(meta.schemaVersion).toBe(1);

    const read = await readCatalog(db, scopeA);
    expect(read).not.toBeNull();
    const oli = read?.products.find((row) => row.id === "produk-oli");
    expect(oli?.stockQty).toBe(7);
    expect(oli?.units.find((unit) => unit.unitId === "unit-dus")?.factor).toBe(12);
    expect(read?.customers[0]?.name).toBe("Budi");
    expect(read?.priceBreaks[0]?.price).toBe(590000);

    const semen = read?.products.find((row) => row.id === "produk-semen");
    expect(semen?.isLow).toBe(true);
  });

  it("membuat satuan dasar kalau units kosong", async () => {
    await hydrateCatalog(
      db,
      scopeA,
      makeSnapshot({
        products: [
          makeProduct({
            units: [],
            baseUnitId: "unit-liter",
            baseUnitName: "liter",
          }),
        ],
      })
    );

    const read = await readCatalog(db, scopeA);
    expect(read?.products[0]?.units).toEqual([
      { unitId: "unit-liter", name: "liter", factor: 1, price: 55000 },
    ]);
  });

  it("mencari dari Dexie berdasarkan nama, SKU, dan barcode", async () => {
    await hydrateCatalog(db, scopeA, makeSnapshot());

    expect((await searchCachedProducts(db, scopeA, "oli"))[0]?.id).toBe(
      "produk-oli"
    );
    expect((await searchCachedProducts(db, scopeA, "SEMEN-1"))[0]?.id).toBe(
      "produk-semen"
    );
    expect((await searchCachedProducts(db, scopeA, "8999001"))[0]?.id).toBe(
      "produk-oli"
    );
  });
});

describe("isolasi tenant, outlet, dan tier", () => {
  it("tenant lain tidak bisa membaca cache tenant ini", async () => {
    await hydrateCatalog(db, scopeA, makeSnapshot());

    expect(await readCatalog(db, scopeB)).toBeNull();
    expect(await searchCachedProducts(db, scopeB, "oli")).toEqual([]);
  });

  it("outlet/tier lain dalam tenant yang sama terisolasi", async () => {
    await hydrateCatalog(db, scopeA, makeSnapshot());

    expect(
      await readCatalog(db, { ...scopeA, outletId: "outlet-2" })
    ).toBeNull();
    expect(
      await readCatalog(db, { ...scopeA, tierId: "tier-grosir" })
    ).toBeNull();
  });

  it("ganti tenant menghapus sisa cache tenant lama", async () => {
    await hydrateCatalog(db, scopeB, makeSnapshot());
    await hydrateCatalog(db, scopeA, makeSnapshot());

    expect(await readCatalog(db, scopeB)).toBeNull();
    expect((await db.products.toArray()).every((row) => row.tenantId === "tenant-a")).toBe(
      true
    );
    expect(
      (await db.customers.toArray()).every((row) => row.tenantId === "tenant-a")
    ).toBe(true);
  });
});

describe("versioning cache", () => {
  it("cache versi lama dianggap kosong dan dibersihkan", async () => {
    await hydrateCatalog(db, scopeA, makeSnapshot());
    const scopeKey = buildScopeKey(scopeA);
    await db.meta.update(scopeKey, { schemaVersion: 0 });

    expect(await readCatalog(db, scopeA)).toBeNull();
    expect(await db.meta.get(scopeKey)).toBeUndefined();
    expect(await db.products.where("scopeKey").equals(scopeKey).count()).toBe(0);
  });

  it("hash berubah saat isi katalog berubah", async () => {
    const first = await hydrateCatalog(
      db,
      scopeA,
      makeSnapshot(),
      new Date("2026-10-26T01:00:00.000Z")
    );

    const cheaper = makeSnapshot({
      products: [makeProduct({ price: 50000 })],
    });
    const second = await hydrateCatalog(
      db,
      scopeA,
      cheaper,
      new Date("2026-10-26T02:00:00.000Z")
    );

    expect(first.payloadHash).not.toBe(second.payloadHash);
    expect(second.lastSyncedAt).toBe("2026-10-26T02:00:00.000Z");
  });
});

describe("data sensitif", () => {
  it("tidak menyimpan cost_price/HPP ke Dexie", async () => {
    const productWithCost = {
      ...makeProduct(),
      cost_price: 41000,
      unit_cost: 41000,
      unitCost: 41000,
      hpp: 41000,
    } as unknown as PosProduct;

    await hydrateCatalog(
      db,
      scopeA,
      makeSnapshot({ products: [productWithCost] })
    );

    const rows = [
      ...(await db.products.toArray()),
      ...(await db.productUnits.toArray()),
      ...(await db.stockLevels.toArray()),
      ...(await db.priceBreaks.toArray()),
      ...(await db.customers.toArray()),
      ...(await db.meta.toArray()),
    ];
    expect(JSON.stringify(rows)).not.toMatch(/cost|hpp/i);
  });
});

describe("clearOfflineCatalog", () => {
  it("menghapus seluruh cache (logout)", async () => {
    await hydrateCatalog(db, scopeA, makeSnapshot());
    await clearOfflineCatalog(db);

    expect(await readCatalog(db, scopeA)).toBeNull();
    expect(await db.products.count()).toBe(0);
    expect(await db.customers.count()).toBe(0);
    expect(await db.meta.count()).toBe(0);
  });
});

describe("applyCachedSale", () => {
  it("mengurangi stok cache dan menandai stok menipis", async () => {
    await hydrateCatalog(db, scopeA, makeSnapshot());

    await applyCachedSale(db, scopeA, [
      { productId: "produk-semen", qtyBase: 1.5 },
    ]);

    const read = await readCatalog(db, scopeA);
    const semen = read?.products.find((row) => row.id === "produk-semen");
    expect(semen?.stockQty).toBe(0.5);
    expect(semen?.isLow).toBe(true);
  });

  it("tidak membuat stok negatif di layar kasir", async () => {
    await hydrateCatalog(db, scopeA, makeSnapshot());

    await applyCachedSale(db, scopeA, [
      { productId: "produk-semen", qtyBase: 99 },
    ]);

    const read = await readCatalog(db, scopeA);
    const semen = read?.products.find((row) => row.id === "produk-semen");
    expect(semen?.stockQty).toBe(0);
  });
});
