import "fake-indexeddb/auto";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { createCatalogDb, type OfflineCatalogDb } from "./catalog-db";
import { buildLocalInvoiceNo, OUTBOX_MAX_ATTEMPTS } from "./outbox-schema";
import {
  claimNextOutboxSale,
  countOutbox,
  enqueueSale,
  listOutbox,
  markOutboxRetry,
  markOutboxSynced,
  pruneOutbox,
  resetStuckSyncing,
  type EnqueueSaleInput,
} from "./outbox-store";

const TENANT = "tenant-a";

function makeInput(overrides: Partial<EnqueueSaleInput> = {}): EnqueueSaleInput {
  return {
    localInvoiceNo: "TMP-ABCD-0001",
    tierId: "tier-umum",
    payload: {
      clientUuid: crypto.randomUUID(),
      tenantId: TENANT,
      outletId: "outlet-1",
      shiftId: "shift-1",
      items: [
        {
          productId: "produk-oli",
          unitId: "unit-liter",
          qty: 2,
          unitPrice: 55000,
          discount: 0,
        },
      ],
      payments: [{ method: "tunai", amount: 110000 }],
    },
    ...overrides,
  };
}

let db: OfflineCatalogDb;

beforeEach(() => {
  db = createCatalogDb(`bengkel-pos-outbox-test-${crypto.randomUUID()}`);
});

afterEach(async () => {
  await db.delete();
});

describe("enqueueSale", () => {
  it("menyimpan transaksi sebagai pending tanpa data HPP", async () => {
    const input = makeInput();
    const row = await enqueueSale(db, input);

    expect(row.state).toBe("pending");
    expect(row.localInvoiceNo).toBe("TMP-ABCD-0001");
    expect(row.clientUuid).toBe(input.payload.clientUuid);

    const stored = await db.outbox.get(input.payload.clientUuid);
    expect(stored?.payload.items[0]?.unitPrice).toBe(55000);
    expect(JSON.stringify(stored)).not.toMatch(/cost|hpp/i);
  });

  it("idempoten: clientUuid sama tidak membuat dua baris", async () => {
    const input = makeInput();
    await enqueueSale(db, input);
    await enqueueSale(db, input);

    expect(await db.outbox.count()).toBe(1);
  });
});

describe("countOutbox", () => {
  it("memisahkan menunggu kirim, perlu review, dan gagal", async () => {
    const a = await enqueueSale(db, makeInput());
    const b = await enqueueSale(db, makeInput());
    const c = await enqueueSale(db, makeInput());

    await markOutboxSynced(db, b.clientUuid, {
      saleId: "sale-b",
      invoiceNo: "INV-2",
      status: "needs_review",
      needsReviewReason: "Stok Oli Mesin 1L tidak cukup",
    });

    for (let attempt = 0; attempt < OUTBOX_MAX_ATTEMPTS; attempt += 1) {
      await markOutboxRetry(db, c.clientUuid, "Gagal jaringan");
    }

    expect(await countOutbox(db, TENANT)).toEqual({
      pending: 1,
      needsReview: 1,
      failed: 1,
    });
    expect(a.state).toBe("pending");
  });

  it("tidak menghitung tenant lain", async () => {
    await enqueueSale(db, makeInput());
    expect(await countOutbox(db, "tenant-b")).toEqual({
      pending: 0,
      needsReview: 0,
      failed: 0,
    });
  });
});

describe("claimNextOutboxSale", () => {
  it("mengambil yang paling lama dan menandainya syncing", async () => {
    const first = await enqueueSale(
      db,
      makeInput({ now: new Date("2026-10-27T08:00:00Z") })
    );
    await enqueueSale(db, makeInput({ now: new Date("2026-10-27T09:00:00Z") }));

    const claimed = await claimNextOutboxSale(db, TENANT);
    expect(claimed?.clientUuid).toBe(first.clientUuid);
    expect(claimed?.state).toBe("syncing");

    const second = await claimNextOutboxSale(db, TENANT);
    expect(second?.clientUuid).not.toBe(first.clientUuid);
    expect(await claimNextOutboxSale(db, TENANT)).toBeNull();
  });
});

describe("markOutboxSynced", () => {
  it("menyimpan nomor resmi saat berhasil", async () => {
    const row = await enqueueSale(db, makeInput());
    await markOutboxSynced(db, row.clientUuid, {
      saleId: "sale-1",
      invoiceNo: "INV-0001",
      status: "paid",
      needsReviewReason: null,
    });

    const stored = await db.outbox.get(row.clientUuid);
    expect(stored?.state).toBe("done");
    expect(stored?.invoiceNo).toBe("INV-0001");
    expect(stored?.saleId).toBe("sale-1");
    expect(stored?.syncedAt).not.toBeNull();
  });

  it("menandai needs_review beserta alasannya", async () => {
    const row = await enqueueSale(db, makeInput());
    await markOutboxSynced(db, row.clientUuid, {
      saleId: "sale-1",
      invoiceNo: "INV-0001",
      status: "needs_review",
      needsReviewReason: "Harga berubah",
    });

    const stored = await db.outbox.get(row.clientUuid);
    expect(stored?.state).toBe("needs_review");
    expect(stored?.needsReviewReason).toBe("Harga berubah");
  });
});

describe("markOutboxRetry", () => {
  it("kembali pending lalu failed setelah batas percobaan", async () => {
    const row = await enqueueSale(db, makeInput());

    await markOutboxRetry(db, row.clientUuid, "Koneksi putus");
    let stored = await db.outbox.get(row.clientUuid);
    expect(stored?.state).toBe("pending");
    expect(stored?.attempts).toBe(1);
    expect(stored?.lastError).toBe("Koneksi putus");

    for (let attempt = 1; attempt < OUTBOX_MAX_ATTEMPTS; attempt += 1) {
      await markOutboxRetry(db, row.clientUuid, "Koneksi putus");
    }
    stored = await db.outbox.get(row.clientUuid);
    expect(stored?.state).toBe("failed");
  });
});

describe("resetStuckSyncing", () => {
  it("mengembalikan baris syncing yang tertinggal ke pending", async () => {
    await enqueueSale(db, makeInput());
    await claimNextOutboxSale(db, TENANT);

    await resetStuckSyncing(db, TENANT);

    const rows = await listOutbox(db, TENANT);
    expect(rows[0]?.state).toBe("pending");
  });
});

describe("pruneOutbox", () => {
  it("hanya menghapus baris done yang sudah lewat masa simpan", async () => {
    const old = await enqueueSale(
      db,
      makeInput({ now: new Date("2026-10-01T00:00:00Z") })
    );
    const fresh = await enqueueSale(db, makeInput());
    const pending = await enqueueSale(db, makeInput());

    for (const row of [old, fresh]) {
      await markOutboxSynced(db, row.clientUuid, {
        saleId: "sale",
        invoiceNo: "INV-1",
        status: "paid",
        needsReviewReason: null,
      });
    }

    await pruneOutbox(db, TENANT, new Date("2026-10-27T00:00:00Z"));

    expect(await db.outbox.get(old.clientUuid)).toBeUndefined();
    expect(await db.outbox.get(fresh.clientUuid)).toBeDefined();
    expect(await db.outbox.get(pending.clientUuid)).toBeDefined();
  });
});

describe("buildLocalInvoiceNo", () => {
  it("memakai awalan perangkat dan nomor urut 4 digit", () => {
    expect(buildLocalInvoiceNo("abcd-1234", 7)).toBe("TMP-ABCD-0007");
    expect(buildLocalInvoiceNo("", 12)).toBe("TMP-POS-0012");
  });
});
