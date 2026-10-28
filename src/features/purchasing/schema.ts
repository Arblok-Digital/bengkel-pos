import { z } from "zod";

export const purchaseOrderItemSchema = z.object({
  productId: z.string().uuid("Produk wajib dipilih"),
  unitId: z.string().uuid("Satuan wajib dipilih"),
  qty: z.coerce
    .number()
    .positive("Qty harus lebih dari 0")
    .max(1000000, "Qty terlalu besar"),
  unitPrice: z.coerce
    .number()
    .int("Harga harus bilangan bulat rupiah")
    .min(0, "Harga tidak boleh negatif")
    .max(Number.MAX_SAFE_INTEGER, "Harga terlalu besar"),
  note: z.string().trim().max(500, "Catatan maksimal 500 karakter").optional(),
});

export const createPurchaseOrderSchema = z.object({
  tenantId: z.string().uuid("Tenant wajib dipilih"),
  outletId: z.string().uuid("Outlet wajib dipilih"),
  supplierId: z.string().uuid("Supplier wajib dipilih"),
  clientUuid: z.string().uuid("client_uuid wajib"),
  note: z.string().trim().max(500, "Catatan maksimal 500 karakter").optional(),
  items: z.array(purchaseOrderItemSchema).min(1, "Minimal satu item PO"),
});
