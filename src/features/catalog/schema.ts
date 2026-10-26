import { z } from "zod";

const categoryName = z
  .string()
  .trim()
  .min(1, "Nama kategori wajib diisi")
  .max(80, "Nama kategori maksimal 80 karakter");

const unitName = z
  .string()
  .trim()
  .min(1, "Nama satuan wajib diisi")
  .max(30, "Nama satuan maksimal 30 karakter");

export const createCategorySchema = z.object({
  tenantId: z.guid(),
  name: categoryName,
  parentId: z.union([z.guid(), z.literal("")]).optional(),
});

export const renameCategorySchema = z.object({
  tenantId: z.guid(),
  id: z.guid(),
  name: categoryName,
});

export const deleteCategorySchema = z.object({
  tenantId: z.guid(),
  id: z.guid(),
});

export const createUnitSchema = z.object({
  tenantId: z.guid(),
  name: unitName,
});

export const renameUnitSchema = z.object({
  tenantId: z.guid(),
  id: z.guid(),
  name: unitName,
});

export const deleteUnitSchema = z.object({
  tenantId: z.guid(),
  id: z.guid(),
});
