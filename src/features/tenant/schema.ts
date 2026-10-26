import { z } from "zod";

export const businessTypeSchema = z.enum(["bengkel", "toko_bangunan", "both"]);

export const onboardingSchema = z.object({
  clientUuid: z.string().uuid("client_uuid tidak valid"),
  name: z
    .string()
    .trim()
    .min(2, "Nama usaha minimal 2 karakter")
    .max(100, "Nama usaha maksimal 100 karakter"),
  businessType: businessTypeSchema,
  outletName: z
    .string()
    .trim()
    .min(2, "Nama outlet minimal 2 karakter")
    .max(100, "Nama outlet maksimal 100 karakter"),
});

export type OnboardingInput = z.infer<typeof onboardingSchema>;
