"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import {
  createProductSchema,
  deleteProductSchema,
  updateProductSchema,
} from "./schema";

export type ProductActionState = { error: string | null };

type Context =
  | { ok: true; supabase: Awaited<ReturnType<typeof createClient>> }
  | { ok: false; error: string };

async function getWriterContext(tenantId: string): Promise<Context> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { ok: false, error: "Sesi tidak valid. Login ulang." };

  const { data } = await supabase
    .from("memberships")
    .select("role")
    .eq("tenant_id", tenantId)
    .eq("user_id", user.id)
    .eq("active", true)
    .maybeSingle();

  if (!data || !["owner", "admin"].includes(data.role)) {
    return { ok: false, error: "Anda tidak berhak mengubah produk." };
  }

  return { ok: true, supabase };
}

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

function mapError(code: string | undefined): string {
  if (code === "23505") return "SKU atau barcode sudah dipakai produk lain.";
  if (code === "23503") return "Kategori atau satuan tidak valid.";
  if (code === "42501") return "Tidak berhak mengubah produk.";
  return "Gagal menyimpan produk.";
}

export async function createProductAction(
  _prev: ProductActionState,
  formData: FormData
): Promise<ProductActionState> {
  const parsed = createProductSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    name: str(formData, "name"),
    sku: str(formData, "sku"),
    barcode: str(formData, "barcode"),
    categoryId: str(formData, "categoryId"),
    baseUnitId: str(formData, "baseUnitId"),
    kind: str(formData, "kind"),
    sellPrice: str(formData, "sellPrice"),
    minStock: str(formData, "minStock") || "0",
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian produk tidak valid.",
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { error } = await ctx.supabase.from("products").insert({
    tenant_id: parsed.data.tenantId,
    name: parsed.data.name,
    sku: parsed.data.sku || null,
    barcode: parsed.data.barcode || null,
    category_id: parsed.data.categoryId || null,
    base_unit_id: parsed.data.baseUnitId,
    kind: parsed.data.kind,
    track_stock: parsed.data.kind === "barang",
    sell_price: parsed.data.sellPrice,
    min_stock: parsed.data.minStock,
    active: true,
  });

  if (error) return { error: mapError(error.code) };

  revalidatePath("/produk");
  redirect("/produk");
}

export async function updateProductAction(
  _prev: ProductActionState,
  formData: FormData
): Promise<ProductActionState> {
  const parsed = updateProductSchema.safeParse({
    id: str(formData, "id"),
    tenantId: str(formData, "tenantId"),
    name: str(formData, "name"),
    sku: str(formData, "sku"),
    barcode: str(formData, "barcode"),
    categoryId: str(formData, "categoryId"),
    baseUnitId: str(formData, "baseUnitId"),
    kind: str(formData, "kind"),
    sellPrice: str(formData, "sellPrice"),
    minStock: str(formData, "minStock") || "0",
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian produk tidak valid.",
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { data, error } = await ctx.supabase
    .from("products")
    .update({
      name: parsed.data.name,
      sku: parsed.data.sku || null,
      barcode: parsed.data.barcode || null,
      category_id: parsed.data.categoryId || null,
      base_unit_id: parsed.data.baseUnitId,
      kind: parsed.data.kind,
      track_stock: parsed.data.kind === "barang",
      sell_price: parsed.data.sellPrice,
      min_stock: parsed.data.minStock,
      active: formData.get("active") === "on",
    })
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) return { error: mapError(error.code) };
  if (!data || data.length === 0) {
    return { error: "Produk tidak ditemukan atau bukan hak Anda." };
  }

  revalidatePath("/produk");
  redirect("/produk");
}

export async function deleteProductAction(
  _prev: ProductActionState,
  formData: FormData
): Promise<ProductActionState> {
  const parsed = deleteProductSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    id: str(formData, "id"),
  });

  if (!parsed.success) {
    return { error: "Data produk tidak valid." };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { data, error } = await ctx.supabase
    .from("products")
    .delete()
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) {
    if (error.code === "23503") {
      return { error: "Produk masih dipakai transaksi." };
    }
    return { error: "Gagal menghapus produk." };
  }
  if (!data || data.length === 0) {
    return { error: "Produk tidak ditemukan atau bukan hak Anda." };
  }

  revalidatePath("/produk");
  redirect("/produk");
}
