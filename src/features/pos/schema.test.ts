import { describe, expect, it } from "vitest";

import { createSaleSchema } from "./schema";

const base = {
  clientUuid: "11111111-1111-1111-1111-111111111111",
  tenantId: "22222222-2222-2222-2222-222222222222",
  outletId: "33333333-3333-3333-3333-333333333333",
  items: [
    {
      productId: "44444444-4444-4444-4444-444444444444",
      unitId: "55555555-5555-5555-5555-555555555555",
      qty: "2",
      unitPrice: "10000",
    },
  ],
  payments: [{ method: "tunai", amount: "20000" }],
};

describe("createSaleSchema", () => {
  it("menerima transaksi tunai sederhana", () => {
    const result = createSaleSchema.parse(base);
    expect(result.items[0]?.qty).toBe(2);
    expect(result.items[0]?.unitPrice).toBe(10000);
    expect(result.items[0]?.discount).toBe(0);
    expect(result.payments[0]?.amount).toBe(20000);
  });

  it("menerima qty desimal (0,5 sak)", () => {
    const result = createSaleSchema.parse({
      ...base,
      items: [{ ...base.items[0], qty: "0.5" }],
    });
    expect(result.items[0]?.qty).toBe(0.5);
  });

  it("menolak keranjang kosong", () => {
    const result = createSaleSchema.safeParse({ ...base, items: [] });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.message).toBe("Minimal satu item");
  });

  it("menolak qty nol atau negatif", () => {
    for (const qty of ["0", "-2"]) {
      const result = createSaleSchema.safeParse({
        ...base,
        items: [{ ...base.items[0], qty }],
      });
      expect(result.success).toBe(false);
    }
  });

  it("menolak harga desimal", () => {
    const result = createSaleSchema.safeParse({
      ...base,
      items: [{ ...base.items[0], unitPrice: "10000.5" }],
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.message).toBe(
      "Harga harus bilangan bulat rupiah"
    );
  });

  it("menolak nominal pembayaran nol", () => {
    const result = createSaleSchema.safeParse({
      ...base,
      payments: [{ method: "tunai", amount: "0" }],
    });
    expect(result.success).toBe(false);
  });

  it("menolak metode pembayaran tidak dikenal", () => {
    const result = createSaleSchema.safeParse({
      ...base,
      payments: [{ method: "bitcoin", amount: "20000" }],
    });
    expect(result.success).toBe(false);
  });

  it("menerima pembayaran campuran", () => {
    const result = createSaleSchema.parse({
      ...base,
      payments: [
        { method: "tunai", amount: "10000" },
        { method: "transfer", amount: "10000", reference: "TRX-1" },
      ],
    });
    expect(result.payments).toHaveLength(2);
  });
});
