import { describe, expect, it } from "vitest";

import { closeShiftSchema, openShiftSchema } from "./schema";

const tenantId = "11111111-1111-1111-1111-111111111111";
const outletId = "22222222-2222-2222-2222-222222222222";
const shiftId = "33333333-3333-3333-3333-333333333333";
const clientUuid = "44444444-4444-4444-4444-444444444444";

describe("openShiftSchema", () => {
  it("menerima modal awal bulat", () => {
    const result = openShiftSchema.parse({
      tenantId,
      outletId,
      clientUuid,
      openingCash: "300000",
    });
    expect(result.openingCash).toBe(300000);
  });

  it("menerima modal awal 0", () => {
    const result = openShiftSchema.parse({
      tenantId,
      outletId,
      clientUuid,
      openingCash: "0",
    });
    expect(result.openingCash).toBe(0);
  });

  it("menolak modal awal negatif", () => {
    const result = openShiftSchema.safeParse({
      tenantId,
      outletId,
      clientUuid,
      openingCash: "-1",
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.message).toBe(
      "Modal awal tidak boleh negatif"
    );
  });

  it("menolak modal awal desimal", () => {
    const result = openShiftSchema.safeParse({
      tenantId,
      outletId,
      clientUuid,
      openingCash: "1000.5",
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.message).toBe(
      "Modal awal harus bilangan bulat rupiah"
    );
  });

  it("menolak client_uuid bukan uuid", () => {
    const result = openShiftSchema.safeParse({
      tenantId,
      outletId,
      clientUuid: "bukan-uuid",
      openingCash: "1000",
    });
    expect(result.success).toBe(false);
  });
});

describe("closeShiftSchema", () => {
  it("menerima uang hitung dan catatan", () => {
    const result = closeShiftSchema.parse({
      tenantId,
      shiftId,
      clientUuid,
      closingCashCounted: "250000",
      note: "  selisih kembalian  ",
    });
    expect(result.closingCashCounted).toBe(250000);
    expect(result.note).toBe("selisih kembalian");
  });

  it("menolak uang hitung negatif", () => {
    const result = closeShiftSchema.safeParse({
      tenantId,
      shiftId,
      clientUuid,
      closingCashCounted: "-5000",
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.message).toBe(
      "Uang dihitung tidak boleh negatif"
    );
  });

  it("menolak catatan lebih dari 500 karakter", () => {
    const result = closeShiftSchema.safeParse({
      tenantId,
      shiftId,
      clientUuid,
      closingCashCounted: "1000",
      note: "x".repeat(501),
    });
    expect(result.success).toBe(false);
  });
});
