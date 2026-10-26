"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import {
  customerSchema,
  deleteCustomerSchema,
  updateCustomerSchema,
} from "./schema";

export type CustomerActionState = { error: string | null };

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
    return { ok: false, error: "Anda tidak berhak mengubah pelanggan." };
  }

  return { ok: true, supabase };
}

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

function mapError(code: string | undefined): string {
  if (code === "23503") return "Tier harga tidak valid.";
  if (code === "23514") return "Nilai pelanggan tidak valid.";
  if (code === "42501") return "Tidak berhak mengubah pelanggan.";
  return "Gagal menyimpan pelanggan.";
}

export async function createCustomerAction(
  _prev: CustomerActionState,
  formData: FormData
): Promise<CustomerActionState> {
  const parsed = customerSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    name: str(formData, "name"),
    phone: str(formData, "phone"),
    address: str(formData, "address"),
    tierId: str(formData, "tierId"),
    creditLimit: str(formData, "creditLimit") || "0",
    notes: str(formData, "notes"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian pelanggan tidak valid.",
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { error } = await ctx.supabase.from("customers").insert({
    tenant_id: parsed.data.tenantId,
    name: parsed.data.name,
    phone: parsed.data.phone || null,
    address: parsed.data.address || null,
    tier_id: parsed.data.tierId || null,
    credit_limit: parsed.data.creditLimit,
    notes: parsed.data.notes || null,
    active: true,
  });

  if (error) return { error: mapError(error.code) };

  revalidatePath("/pelanggan");
  redirect("/pelanggan");
}

export async function updateCustomerAction(
  _prev: CustomerActionState,
  formData: FormData
): Promise<CustomerActionState> {
  const parsed = updateCustomerSchema.safeParse({
    id: str(formData, "id"),
    tenantId: str(formData, "tenantId"),
    name: str(formData, "name"),
    phone: str(formData, "phone"),
    address: str(formData, "address"),
    tierId: str(formData, "tierId"),
    creditLimit: str(formData, "creditLimit") || "0",
    notes: str(formData, "notes"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian pelanggan tidak valid.",
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { data, error } = await ctx.supabase
    .from("customers")
    .update({
      name: parsed.data.name,
      phone: parsed.data.phone || null,
      address: parsed.data.address || null,
      tier_id: parsed.data.tierId || null,
      credit_limit: parsed.data.creditLimit,
      notes: parsed.data.notes || null,
      active: formData.get("active") === "on",
    })
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) return { error: mapError(error.code) };
  if (!data || data.length === 0) {
    return { error: "Pelanggan tidak ditemukan atau bukan hak Anda." };
  }

  revalidatePath("/pelanggan");
  redirect("/pelanggan");
}

export async function deleteCustomerAction(
  _prev: CustomerActionState,
  formData: FormData
): Promise<CustomerActionState> {
  const parsed = deleteCustomerSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    id: str(formData, "id"),
  });

  if (!parsed.success) return { error: "Data pelanggan tidak valid." };

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { data, error } = await ctx.supabase
    .from("customers")
    .delete()
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) {
    if (error.code === "23503") {
      return { error: "Pelanggan masih dipakai transaksi." };
    }
    return { error: "Gagal menghapus pelanggan." };
  }
  if (!data || data.length === 0) {
    return { error: "Pelanggan tidak ditemukan atau bukan hak Anda." };
  }

  revalidatePath("/pelanggan");
  redirect("/pelanggan");
}
