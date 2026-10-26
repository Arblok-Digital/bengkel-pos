"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import {
  addPriceBreakSchema,
  addProductUnitSchema,
  deletePricingRowSchema,
  upsertProductPriceSchema,
} from "./schema";

export type PricingActionState = { error: string | null; success: string | null };

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
    return { ok: false, error: "Anda tidak berhak mengubah harga." };
  }

  return { ok: true, supabase };
}

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

function mapError(code: string | undefined): string {
  if (code === "23505") return "Data harga itu sudah ada.";
  if (code === "23503") return "Satuan/tier/produk tidak valid.";
  if (code === "42501") return "Tidak berhak mengubah harga.";
  return "Gagal menyimpan data harga.";
}

function refresh(productId: string) {
  revalidatePath("/produk");
  revalidatePath(`/produk/${productId}/harga`);
}

export async function addProductUnitAction(
  _prev: PricingActionState,
  formData: FormData
): Promise<PricingActionState> {
  const parsed = addProductUnitSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    productId: str(formData, "productId"),
    unitId: str(formData, "unitId"),
    factorToBase: str(formData, "factorToBase"),
    sellPrice: str(formData, "sellPrice"),
    barcode: str(formData, "barcode"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Data konversi tidak valid.",
      success: null,
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { error } = await ctx.supabase.from("product_units").insert({
    tenant_id: parsed.data.tenantId,
    product_id: parsed.data.productId,
    unit_id: parsed.data.unitId,
    factor_to_base: parsed.data.factorToBase,
    sell_price: parsed.data.sellPrice,
    barcode: parsed.data.barcode || null,
  });

  if (error) return { error: mapError(error.code), success: null };

  refresh(parsed.data.productId);
  return { error: null, success: "Konversi satuan ditambahkan." };
}

export async function deleteProductUnitAction(
  _prev: PricingActionState,
  formData: FormData
): Promise<PricingActionState> {
  const parsed = deletePricingRowSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    id: str(formData, "id"),
    productId: str(formData, "productId"),
  });

  if (!parsed.success) return { error: "Data tidak valid.", success: null };

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { data, error } = await ctx.supabase
    .from("product_units")
    .delete()
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) return { error: mapError(error.code), success: null };
  if (!data || data.length === 0) {
    return { error: "Data tidak ditemukan atau bukan hak Anda.", success: null };
  }

  refresh(parsed.data.productId);
  return { error: null, success: "Konversi dihapus." };
}

export async function upsertProductPriceAction(
  _prev: PricingActionState,
  formData: FormData
): Promise<PricingActionState> {
  const parsed = upsertProductPriceSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    productId: str(formData, "productId"),
    tierId: str(formData, "tierId"),
    unitId: str(formData, "unitId"),
    price: str(formData, "price"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Data harga tier tidak valid.",
      success: null,
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { error } = await ctx.supabase.from("product_prices").upsert(
    {
      tenant_id: parsed.data.tenantId,
      product_id: parsed.data.productId,
      tier_id: parsed.data.tierId,
      unit_id: parsed.data.unitId,
      price: parsed.data.price,
    },
    { onConflict: "tenant_id,product_id,tier_id,unit_id" }
  );

  if (error) return { error: mapError(error.code), success: null };

  refresh(parsed.data.productId);
  return { error: null, success: "Harga tier disimpan." };
}

export async function deleteProductPriceAction(
  _prev: PricingActionState,
  formData: FormData
): Promise<PricingActionState> {
  const parsed = deletePricingRowSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    id: str(formData, "id"),
    productId: str(formData, "productId"),
  });

  if (!parsed.success) return { error: "Data tidak valid.", success: null };

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { data, error } = await ctx.supabase
    .from("product_prices")
    .delete()
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) return { error: mapError(error.code), success: null };
  if (!data || data.length === 0) {
    return { error: "Data tidak ditemukan atau bukan hak Anda.", success: null };
  }

  refresh(parsed.data.productId);
  return { error: null, success: "Harga tier dihapus." };
}

export async function addPriceBreakAction(
  _prev: PricingActionState,
  formData: FormData
): Promise<PricingActionState> {
  const parsed = addPriceBreakSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    productId: str(formData, "productId"),
    unitId: str(formData, "unitId"),
    minQty: str(formData, "minQty"),
    price: str(formData, "price"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Data harga grosir tidak valid.",
      success: null,
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { error } = await ctx.supabase.from("price_breaks").insert({
    tenant_id: parsed.data.tenantId,
    product_id: parsed.data.productId,
    unit_id: parsed.data.unitId,
    min_qty: parsed.data.minQty,
    price: parsed.data.price,
  });

  if (error) return { error: mapError(error.code), success: null };

  refresh(parsed.data.productId);
  return { error: null, success: "Harga grosir ditambahkan." };
}

export async function deletePriceBreakAction(
  _prev: PricingActionState,
  formData: FormData
): Promise<PricingActionState> {
  const parsed = deletePricingRowSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    id: str(formData, "id"),
    productId: str(formData, "productId"),
  });

  if (!parsed.success) return { error: "Data tidak valid.", success: null };

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { data, error } = await ctx.supabase
    .from("price_breaks")
    .delete()
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) return { error: mapError(error.code), success: null };
  if (!data || data.length === 0) {
    return { error: "Data tidak ditemukan atau bukan hak Anda.", success: null };
  }

  refresh(parsed.data.productId);
  return { error: null, success: "Harga grosir dihapus." };
}
