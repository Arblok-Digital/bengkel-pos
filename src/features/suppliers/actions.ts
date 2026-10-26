"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import {
  deleteSupplierSchema,
  supplierSchema,
  updateSupplierSchema,
} from "./schema";

export type SupplierActionState = { error: string | null };

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
    return { ok: false, error: "Anda tidak berhak mengubah pemasok." };
  }

  return { ok: true, supabase };
}

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

function mapError(code: string | undefined): string {
  if (code === "23514") return "Termin pembayaran tidak valid.";
  if (code === "42501") return "Tidak berhak mengubah pemasok.";
  return "Gagal menyimpan pemasok.";
}

export async function createSupplierAction(
  _prev: SupplierActionState,
  formData: FormData
): Promise<SupplierActionState> {
  const parsed = supplierSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    name: str(formData, "name"),
    phone: str(formData, "phone"),
    address: str(formData, "address"),
    paymentTermsDays: str(formData, "paymentTermsDays") || "0",
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian pemasok tidak valid.",
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { error } = await ctx.supabase.from("suppliers").insert({
    tenant_id: parsed.data.tenantId,
    name: parsed.data.name,
    phone: parsed.data.phone || null,
    address: parsed.data.address || null,
    payment_terms_days: parsed.data.paymentTermsDays,
    active: true,
  });

  if (error) return { error: mapError(error.code) };

  revalidatePath("/pemasok");
  redirect("/pemasok");
}

export async function updateSupplierAction(
  _prev: SupplierActionState,
  formData: FormData
): Promise<SupplierActionState> {
  const parsed = updateSupplierSchema.safeParse({
    id: str(formData, "id"),
    tenantId: str(formData, "tenantId"),
    name: str(formData, "name"),
    phone: str(formData, "phone"),
    address: str(formData, "address"),
    paymentTermsDays: str(formData, "paymentTermsDays") || "0",
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian pemasok tidak valid.",
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { data, error } = await ctx.supabase
    .from("suppliers")
    .update({
      name: parsed.data.name,
      phone: parsed.data.phone || null,
      address: parsed.data.address || null,
      payment_terms_days: parsed.data.paymentTermsDays,
      active: formData.get("active") === "on",
    })
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) return { error: mapError(error.code) };
  if (!data || data.length === 0) {
    return { error: "Pemasok tidak ditemukan atau bukan hak Anda." };
  }

  revalidatePath("/pemasok");
  redirect("/pemasok");
}

export async function deleteSupplierAction(
  _prev: SupplierActionState,
  formData: FormData
): Promise<SupplierActionState> {
  const parsed = deleteSupplierSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    id: str(formData, "id"),
  });

  if (!parsed.success) return { error: "Data pemasok tidak valid." };

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { data, error } = await ctx.supabase
    .from("suppliers")
    .delete()
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) {
    if (error.code === "23503") {
      return { error: "Pemasok masih dipakai transaksi." };
    }
    return { error: "Gagal menghapus pemasok." };
  }
  if (!data || data.length === 0) {
    return { error: "Pemasok tidak ditemukan atau bukan hak Anda." };
  }

  revalidatePath("/pemasok");
  redirect("/pemasok");
}
