import { z } from "zod";

export const staffRoleSchema = z.enum(["admin", "kasir", "mekanik", "gudang"]);

export const addStaffSchema = z.object({
  tenantId: z.guid(),
  email: z.email("Email tidak valid").trim().toLowerCase(),
  password: z
    .union([z.literal(""), z.string().min(8).max(72)])
    .optional(),
  role: staffRoleSchema,
});

export const updateStaffRoleSchema = z.object({
  tenantId: z.guid(),
  userId: z.guid(),
  role: staffRoleSchema,
});

export const setStaffActiveSchema = z.object({
  tenantId: z.guid(),
  userId: z.guid(),
  active: z.enum(["true", "false"]),
});
