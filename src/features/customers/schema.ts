import { z } from "zod";

export const customerSchema = z.object({
  tenantId: z.guid(),
  name: z
    .string()
    .trim()
    .min(1, "Nama pelanggan wajib diisi")
    .max(120, "Nama maksimal 120 karakter"),
  phone: z.string().trim().max(30).optional(),
  address: z.string().trim().max(300).optional(),
  tierId: z.union([z.guid(), z.literal("")]).optional(),
  creditLimit: z.coerce
    .number()
    .int("Limit kredit harus bilangan bulat")
    .min(0, "Limit kredit tidak boleh negatif")
    .max(Number.MAX_SAFE_INTEGER),
  notes: z.string().trim().max(500).optional(),
});

export const updateCustomerSchema = customerSchema.extend({ id: z.guid() });

export const deleteCustomerSchema = z.object({
  tenantId: z.guid(),
  id: z.guid(),
});
