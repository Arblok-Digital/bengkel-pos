import { z } from "zod";

export const salePaymentMethodSchema = z.enum([
  "tunai",
  "transfer",
  "qris",
  "debit",
  "kredit_tempo",
]);

export const saleItemSchema = z.object({
  productId: z.guid(),
  unitId: z.guid(),
  qty: z.coerce.number().positive("Qty harus lebih dari 0"),
  unitPrice: z.coerce
    .number()
    .int("Harga harus bilangan bulat rupiah")
    .min(0, "Harga tidak boleh negatif"),
  discount: z.coerce
    .number()
    .int("Diskon harus bilangan bulat rupiah")
    .min(0, "Diskon tidak boleh negatif")
    .default(0),
  note: z.string().trim().max(200, "Catatan item maksimal 200 karakter").optional(),
});

export const salePaymentSchema = z.object({
  method: salePaymentMethodSchema,
  amount: z.coerce
    .number()
    .int("Nominal harus bilangan bulat rupiah")
    .positive("Nominal pembayaran harus lebih dari 0"),
  reference: z
    .string()
    .trim()
    .max(100, "Referensi maksimal 100 karakter")
    .optional(),
});

export const createSaleSchema = z.object({
  clientUuid: z.guid(),
  tenantId: z.guid(),
  outletId: z.guid(),
  customerId: z.guid().optional(),
  shiftId: z.guid().optional(),
  note: z.string().trim().max(500, "Catatan maksimal 500 karakter").optional(),
  items: z.array(saleItemSchema).min(1, "Minimal satu item"),
  payments: z.array(salePaymentSchema).min(1, "Minimal satu pembayaran"),
});

export type CreateSaleInput = z.infer<typeof createSaleSchema>;

/** Payload replay outbox: sama dengan create_sale + nomor sementara perangkat. */
export const syncSaleSchema = createSaleSchema.extend({
  localInvoiceNo: z
    .string()
    .trim()
    .min(1, "Nomor sementara wajib diisi")
    .max(60, "Nomor sementara terlalu panjang"),
});

export type SyncSaleInput = z.infer<typeof syncSaleSchema>;

export const priceRequestSchema = z.object({
  productId: z.guid(),
  unitId: z.guid(),
  qty: z.coerce.number().positive("Qty harus lebih dari 0"),
  tierId: z.guid().nullable().optional(),
});
