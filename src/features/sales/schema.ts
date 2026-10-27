import { z } from "zod";

export const receiptSettingsSchema = z.object({
  tenantId: z.guid(),
  storeName: z
    .string()
    .trim()
    .max(80, "Nama toko maksimal 80 karakter")
    .optional(),
  address: z
    .string()
    .trim()
    .max(200, "Alamat maksimal 200 karakter")
    .optional(),
  phone: z.string().trim().max(30, "Telepon maksimal 30 karakter").optional(),
  footer: z
    .string()
    .trim()
    .max(300, "Footer maksimal 300 karakter")
    .optional(),
  logoUrl: z
    .union([z.literal(""), z.string().trim().url("URL logo tidak valid")])
    .optional(),
  paperWidth: z.enum(["58", "80"]),
  hideTaxPercent: z.boolean(),
  showMechanic: z.boolean(),
});

export type ReceiptSettingsInput = z.infer<typeof receiptSettingsSchema>;

export const voidSaleSchema = z.object({
  saleId: z.guid(),
  reason: z
    .string()
    .trim()
    .min(3, "Alasan void wajib diisi (minimal 3 karakter)")
    .max(300, "Alasan maksimal 300 karakter"),
  clientUuid: z.guid(),
});

export const saleReturnSchema = z.object({
  saleId: z.guid(),
  reason: z
    .string()
    .trim()
    .min(3, "Alasan retur wajib diisi (minimal 3 karakter)")
    .max(300, "Alasan maksimal 300 karakter"),
  clientUuid: z.guid(),
  items: z
    .array(
      z.object({
        saleItemId: z.guid(),
        qty: z.coerce.number().positive("Qty retur harus lebih dari 0"),
      })
    )
    .min(1, "Isi qty retur minimal satu item"),
});
