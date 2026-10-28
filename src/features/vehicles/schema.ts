import { z } from "zod";

export const vehicleSchema = z.object({
  tenantId: z.guid(),
  customerId: z.guid("Pelanggan wajib dipilih"),
  plateNo: z
    .string()
    .trim()
    .toUpperCase()
    .min(1, "Nomor polisi wajib diisi")
    .max(20, "Nomor polisi maksimal 20 karakter"),
  brand: z.string().trim().max(50, "Merk maksimal 50 karakter").optional(),
  model: z.string().trim().max(50, "Model maksimal 50 karakter").optional(),
  year: z.coerce
    .number()
    .int("Tahun harus bilangan bulat")
    .min(1900, "Tahun minimal 1900")
    .max(2100, "Tahun maksimal 2100")
    .optional()
    .nullable(),
  vin: z.string().trim().max(50, "VIN maksimal 50 karakter").optional().nullable(),
  lastOdometer: z.coerce
    .number()
    .int("Odometer harus bilangan bulat")
    .min(0, "Odometer tidak boleh negatif")
    .optional()
    .nullable(),
  active: z.boolean().default(true),
});

export const updateVehicleSchema = vehicleSchema.extend({
  id: z.guid(),
});

export const deleteVehicleSchema = z.object({
  tenantId: z.guid(),
  id: z.guid(),
});
