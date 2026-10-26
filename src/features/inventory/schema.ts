import { z } from "zod";

export const stockAdjustmentSchema = z.object({
  tenantId: z.guid(),
  productId: z.guid(),
  outletId: z.guid(),
  qtyBase: z.coerce
    .number()
    .refine((value) => value !== 0, "Qty tidak boleh 0"),
  reason: z
    .string()
    .trim()
    .min(3, "Alasan wajib diisi (minimal 3 karakter)")
    .max(500, "Alasan maksimal 500 karakter"),
  clientUuid: z.guid(),
});
