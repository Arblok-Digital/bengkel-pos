"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import {
  createCategorySchema,
  createUnitSchema,
  deleteCategorySchema,
  deleteUnitSchema,
  renameCategorySchema,
  renameUnitSchema,
} from "./schema";

export type CatalogActionState = {
  error: string | null;
  success: string | null;
};

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
    return { ok: false, error: "Anda tidak berhak mengubah katalog." };
  }

  return { ok: true, supabase };
}

function formString(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

export async function createCategoryAction(
  _prev: CatalogActionState,
  formData: FormData
): Promise<CatalogActionState> {
  const parsed = createCategorySchema.safeParse({
    tenantId: formString(formData, "tenantId"),
    name: formString(formData, "name"),
    parentId: formString(formData, "parentId"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Nama kategori tidak valid.",
      success: null,
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { error } = await ctx.supabase.from("categories").insert({
    tenant_id: parsed.data.tenantId,
    name: parsed.data.name,
    parent_id: parsed.data.parentId || null,
  });

  if (error) {
    if (error.code === "23503") {
      return { error: "Kategori induk tidak valid.", success: null };
    }
    return { error: "Gagal menambah kategori.", success: null };
  }

  revalidatePath("/katalog");
  return { error: null, success: "Kategori ditambahkan." };
}

export async function renameCategoryAction(
  _prev: CatalogActionState,
  formData: FormData
): Promise<CatalogActionState> {
  const parsed = renameCategorySchema.safeParse({
    tenantId: formString(formData, "tenantId"),
    id: formString(formData, "id"),
    name: formString(formData, "name"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Nama kategori tidak valid.",
      success: null,
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { data, error } = await ctx.supabase
    .from("categories")
    .update({ name: parsed.data.name })
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) return { error: "Gagal mengubah kategori.", success: null };
  if (!data || data.length === 0) {
    return { error: "Kategori tidak ditemukan atau bukan hak Anda.", success: null };
  }

  revalidatePath("/katalog");
  return { error: null, success: "Kategori diperbarui." };
}

export async function deleteCategoryAction(
  _prev: CatalogActionState,
  formData: FormData
): Promise<CatalogActionState> {
  const parsed = deleteCategorySchema.safeParse({
    tenantId: formString(formData, "tenantId"),
    id: formString(formData, "id"),
  });

  if (!parsed.success) {
    return { error: "Data kategori tidak valid.", success: null };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { data, error } = await ctx.supabase
    .from("categories")
    .delete()
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) {
    if (error.code === "23503") {
      return {
        error: "Kategori masih dipakai sub-kategori/produk.",
        success: null,
      };
    }
    return { error: "Gagal menghapus kategori.", success: null };
  }
  if (!data || data.length === 0) {
    return { error: "Kategori tidak ditemukan atau bukan hak Anda.", success: null };
  }

  revalidatePath("/katalog");
  return { error: null, success: "Kategori dihapus." };
}

export async function createUnitAction(
  _prev: CatalogActionState,
  formData: FormData
): Promise<CatalogActionState> {
  const parsed = createUnitSchema.safeParse({
    tenantId: formString(formData, "tenantId"),
    name: formString(formData, "name"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Nama satuan tidak valid.",
      success: null,
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { error } = await ctx.supabase.from("units").insert({
    tenant_id: parsed.data.tenantId,
    name: parsed.data.name,
  });

  if (error) {
    if (error.code === "23505") {
      return { error: "Satuan dengan nama itu sudah ada.", success: null };
    }
    return { error: "Gagal menambah satuan.", success: null };
  }

  revalidatePath("/katalog");
  return { error: null, success: "Satuan ditambahkan." };
}

export async function renameUnitAction(
  _prev: CatalogActionState,
  formData: FormData
): Promise<CatalogActionState> {
  const parsed = renameUnitSchema.safeParse({
    tenantId: formString(formData, "tenantId"),
    id: formString(formData, "id"),
    name: formString(formData, "name"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Nama satuan tidak valid.",
      success: null,
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { data, error } = await ctx.supabase
    .from("units")
    .update({ name: parsed.data.name })
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) {
    if (error.code === "23505") {
      return { error: "Satuan dengan nama itu sudah ada.", success: null };
    }
    return { error: "Gagal mengubah satuan.", success: null };
  }
  if (!data || data.length === 0) {
    return { error: "Satuan tidak ditemukan atau bukan hak Anda.", success: null };
  }

  revalidatePath("/katalog");
  return { error: null, success: "Satuan diperbarui." };
}

export async function deleteUnitAction(
  _prev: CatalogActionState,
  formData: FormData
): Promise<CatalogActionState> {
  const parsed = deleteUnitSchema.safeParse({
    tenantId: formString(formData, "tenantId"),
    id: formString(formData, "id"),
  });

  if (!parsed.success) {
    return { error: "Data satuan tidak valid.", success: null };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { data, error } = await ctx.supabase
    .from("units")
    .delete()
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) {
    if (error.code === "23503") {
      return { error: "Satuan masih dipakai produk.", success: null };
    }
    return { error: "Gagal menghapus satuan.", success: null };
  }
  if (!data || data.length === 0) {
    return { error: "Satuan tidak ditemukan atau bukan hak Anda.", success: null };
  }

  revalidatePath("/katalog");
  return { error: null, success: "Satuan dihapus." };
}
