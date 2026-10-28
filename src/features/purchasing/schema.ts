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

export const receiveGoodsItemSchema = z.object({
  productId: z.string().uuid("Produk wajib dipilih"),
  unitId: z.string().uuid("Satuan wajib dipilih"),
  qty: z.coerce
    .number()
    .positive("Qty harus lebih dari 0")
    .max(1000000, "Qty terlalu besar"),
  unitCost: z.coerce
    .number()
    .int("Harga pokok harus bilangan bulat rupiah")
    .min(0, "Harga pokok tidak boleh negatif")
    .max(Number.MAX_SAFE_INTEGER, "Harga pokok terlalu besar"),
  purchaseOrderItemId: z.string().uuid().optional().nullable(),
  note: z.string().trim().max(500, "Catatan maksimal 500 karakter").optional(),
});

export const receiveGoodsSchema = z.object({
  tenantId: z.string().uuid("Tenant wajib dipilih"),
  outletId: z.string().uuid("Outlet wajib dipilih"),
  supplierId: z.string().uuid("Supplier wajib dipilih"),
  purchaseOrderId: z.string().uuid().optional().nullable(),
  clientUuid: z.string().uuid("client_uuid wajib"),
  note: z.string().trim().max(500, "Catatan maksimal 500 karakter").optional(),
  items: z.array(receiveGoodsItemSchema).min(1, "Minimal satu item penerimaan"),
});
