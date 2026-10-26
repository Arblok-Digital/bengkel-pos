import { z } from "zod";

export const supplierSchema = z.object({
  tenantId: z.guid(),
  name: z
    .string()
    .trim()
    .min(1, "Nama pemasok wajib diisi")
    .max(120, "Nama maksimal 120 karakter"),
  phone: z.string().trim().max(30).optional(),
  address: z.string().trim().max(300).optional(),
  paymentTermsDays: z.coerce
    .number()
    .int("Termin harus bilangan bulat")
    .min(0, "Termin tidak boleh negatif")
    .max(3650),
});

export const updateSupplierSchema = supplierSchema.extend({ id: z.guid() });

export const deleteSupplierSchema = z.object({
  tenantId: z.guid(),
  id: z.guid(),
});
