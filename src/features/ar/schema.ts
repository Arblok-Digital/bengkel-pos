import { z } from "zod";

export const payReceivableSchema = z.object({
  tenantId: z.guid(),
  receivableId: z.guid(),
  amount: z.coerce
    .number()
    .int("Nominal harus bilangan bulat rupiah")
    .positive("Nominal pembayaran harus lebih dari 0"),
  method: z.enum(["tunai", "transfer", "qris", "debit"]),
  reference: z
    .string()
    .trim()
    .max(100, "Referensi maksimal 100 karakter")
    .optional(),
});

export type PayReceivableInput = z.infer<typeof payReceivableSchema>;
