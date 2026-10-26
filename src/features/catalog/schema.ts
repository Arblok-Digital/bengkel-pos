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

export const productKindSchema = z.enum(["barang", "jasa", "paket"]);

export const createProductSchema = z.object({
  tenantId: z.guid(),
  name: z
    .string()
    .trim()
    .min(1, "Nama produk wajib diisi")
    .max(120, "Nama produk maksimal 120 karakter"),
  sku: z.string().trim().max(40, "SKU maksimal 40 karakter").optional(),
  barcode: z
    .string()
    .trim()
    .max(60, "Barcode maksimal 60 karakter")
    .optional(),
  categoryId: z.union([z.guid(), z.literal("")]).optional(),
  baseUnitId: z
    .string()
    .min(1, "Satuan wajib dipilih")
    .pipe(z.guid("Satuan tidak valid")),
  kind: productKindSchema,
  sellPrice: z.coerce
    .number()
    .int("Harga jual harus bilangan bulat")
    .min(0, "Harga jual tidak boleh negatif")
    .max(Number.MAX_SAFE_INTEGER),
  minStock: z.coerce
    .number()
    .min(0, "Stok minimum tidak boleh negatif")
    .max(1_000_000_000),
});

export const updateProductSchema = createProductSchema.extend({
  id: z.guid(),
});

export const deleteProductSchema = z.object({
  tenantId: z.guid(),
  id: z.guid(),
});

export const addProductUnitSchema = z.object({
  tenantId: z.guid(),
  productId: z.guid(),
  unitId: z.guid(),
  factorToBase: z.coerce
    .number()
    .positive("Faktor konversi harus lebih dari 0"),
  sellPrice: z.coerce.number().int().min(0, "Harga tidak boleh negatif"),
  barcode: z.string().trim().max(60).optional(),
});

export const deletePricingRowSchema = z.object({
  tenantId: z.guid(),
  id: z.guid(),
  productId: z.guid(),
});

export const upsertProductPriceSchema = z.object({
  tenantId: z.guid(),
  productId: z.guid(),
  tierId: z.guid(),
  unitId: z.guid(),
  price: z.coerce.number().int().min(0, "Harga tidak boleh negatif"),
});

export const addPriceBreakSchema = z.object({
  tenantId: z.guid(),
  productId: z.guid(),
  unitId: z.guid(),
  minQty: z.coerce.number().positive("Minimal qty harus lebih dari 0"),
  price: z.coerce.number().int().min(0, "Harga tidak boleh negatif"),
});
