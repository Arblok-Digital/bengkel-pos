import { z } from "zod";

export const openShiftSchema = z.object({
  tenantId: z.guid(),
  outletId: z.guid(),
  clientUuid: z.guid(),
  openingCash: z.coerce
    .number()
    .int("Modal awal harus bilangan bulat rupiah")
    .min(0, "Modal awal tidak boleh negatif")
    .max(Number.MAX_SAFE_INTEGER),
});

export const closeShiftSchema = z.object({
  tenantId: z.guid(),
  shiftId: z.guid(),
  clientUuid: z.guid(),
  closingCashCounted: z.coerce
    .number()
    .int("Uang dihitung harus bilangan bulat rupiah")
    .min(0, "Uang dihitung tidak boleh negatif")
    .max(Number.MAX_SAFE_INTEGER),
  note: z.string().trim().max(500, "Catatan maksimal 500 karakter").optional(),
});
