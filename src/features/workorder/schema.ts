import { z } from "zod";

export const workOrderSchema = z.object({
  tenantId: z.guid(),
  outletId: z.guid(),
  customerId: z.guid("Pelanggan wajib dipilih"),
  vehicleId: z.guid("Kendaraan wajib dipilih"),
  odometer: z.coerce
    .number()
    .int("Odometer harus bilangan bulat")
    .min(0, "Odometer tidak boleh negatif")
    .optional()
    .nullable(),
  complaint: z
    .string()
    .trim()
    .min(1, "Keluhan wajib diisi")
    .max(1000, "Keluhan maksimal 1000 karakter"),
  diagnosis: z.string().trim().max(1000, "Diagnosis maksimal 1000 karakter").optional().nullable(),
  mechanicId: z.guid().optional().nullable(),
  estimateTotal: z.coerce
    .number()
    .int("Estimasi total harus bilangan bulat")
    .min(0, "Estimasi total tidak boleh negatif")
    .optional()
    .nullable(),
});

export const workOrderStatusSchema = z.object({
  woId: z.guid(),
  status: z.enum([
    "antri",
    "dikerjakan",
    "menunggu_part",
    "selesai",
    "ditagih",
    "dibatalkan",
  ]),
});

export const workOrderItemSchema = z.object({
  productId: z.guid("Produk wajib dipilih"),
  unitId: z.guid("Satuan wajib dipilih"),
  qty: z.coerce.number().positive("Qty harus lebih dari 0"),
  unitPrice: z.coerce.number().int().min(0, "Harga tidak boleh negatif"),
  note: z.string().trim().optional().nullable(),
});
