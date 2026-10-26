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

export const createOpnameSchema = z.object({
  tenantId: z.guid(),
  outletId: z.guid(),
  note: z.string().trim().max(500, "Catatan maksimal 500 karakter").optional(),
});

export const opnameIdSchema = z.object({
  opnameId: z.guid(),
  tenantId: z.guid(),
});
