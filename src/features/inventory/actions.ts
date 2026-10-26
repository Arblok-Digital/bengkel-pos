"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import type { Json } from "@/lib/supabase/types";
import {
  createOpnameSchema,
  opnameIdSchema,
  stockAdjustmentSchema,
} from "./schema";

export type StockAdjustmentState = { error: string | null };
export type OpnameActionState = { error: string | null; success: string | null };

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

export async function adjustStockAction(
  _prev: StockAdjustmentState,
  formData: FormData
): Promise<StockAdjustmentState> {
  const parsed = stockAdjustmentSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    productId: str(formData, "productId"),
    outletId: str(formData, "outletId"),
    qtyBase: str(formData, "qtyBase"),
    reason: str(formData, "reason"),
    clientUuid: str(formData, "clientUuid"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian penyesuaian tidak valid.",
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("adjust_stock", {
    p_tenant_id: parsed.data.tenantId,
    p_product_id: parsed.data.productId,
    p_outlet_id: parsed.data.outletId,
    p_qty_base: parsed.data.qtyBase,
    p_reason: parsed.data.reason,
    p_client_uuid: parsed.data.clientUuid,
  });

  if (error) {
    if (
      error.message.includes("Alasan") ||
      error.message.includes("Qty") ||
      error.message.includes("Tidak berhak") ||
      error.message.includes("tidak ditemukan") ||
      error.message.includes("tidak melacak stok") ||
      error.message.includes("client_uuid")
    ) {
      return { error: error.message };
    }
    return { error: "Gagal menyesuaikan stok." };
  }
  if (!data) {
    return { error: "Gagal menyesuaikan stok." };
  }

  revalidatePath("/stok");
  redirect("/stok");
}

export async function createOpnameAction(
  _prev: OpnameActionState,
  formData: FormData
): Promise<OpnameActionState> {
  const parsed = createOpnameSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    outletId: str(formData, "outletId"),
    note: str(formData, "note"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian opname tidak valid.",
      success: null,
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_stock_opname", {
    p_tenant_id: parsed.data.tenantId,
    p_outlet_id: parsed.data.outletId,
    p_note: parsed.data.note || null,
  });

  if (error || !data) {
    if (error?.message.includes("berhak")) {
      return { error: error.message, success: null };
    }
    return { error: "Gagal membuat opname stok.", success: null };
  }

  revalidatePath("/stok/opname");
  redirect(`/stok/opname/${data}`);
}

export async function saveOpnameCountsAction(
  _prev: OpnameActionState,
  formData: FormData
): Promise<OpnameActionState> {
  const parsed = opnameIdSchema.safeParse({
    opnameId: str(formData, "opnameId"),
    tenantId: str(formData, "tenantId"),
  });

  if (!parsed.success) {
    return { error: "Data opname tidak valid.", success: null };
  }

  const counts: { item_id: string; counted_qty: number }[] = [];
  for (const [key, value] of formData.entries()) {
    if (!key.startsWith("count_") || typeof value !== "string") continue;
    if (value.trim() === "") continue;
    const qty = Number(value);
    if (!Number.isFinite(qty) || qty < 0) {
      return {
        error: `Hitungan tidak valid untuk salah satu item.`,
        success: null,
      };
    }
    counts.push({ item_id: key.slice("count_".length), counted_qty: qty });
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("save_stock_opname_counts", {
    p_opname_id: parsed.data.opnameId,
    p_counts: counts as unknown as Json,
  });

  if (error) {
    if (
      error.message.includes("berhak") ||
      error.message.includes("draft") ||
      error.message.includes("negatif")
    ) {
      return { error: error.message, success: null };
    }
    return { error: "Gagal menyimpan hitungan.", success: null };
  }

  revalidatePath(`/stok/opname/${parsed.data.opnameId}`);
  return {
    error: null,
    success: `${data ?? counts.length} hitungan disimpan.`,
  };
}

export async function postOpnameAction(
  _prev: OpnameActionState,
  formData: FormData
): Promise<OpnameActionState> {
  const parsed = opnameIdSchema.safeParse({
    opnameId: str(formData, "opnameId"),
    tenantId: str(formData, "tenantId"),
  });

  if (!parsed.success) {
    return { error: "Data opname tidak valid.", success: null };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("post_stock_opname", {
    p_opname_id: parsed.data.opnameId,
  });

  if (error) {
    if (
      error.message.includes("berhak") ||
      error.message.includes("draft") ||
      error.message.includes("Belum ada")
    ) {
      return { error: error.message, success: null };
    }
    return { error: "Gagal memposting opname.", success: null };
  }

  revalidatePath("/stok");
  revalidatePath("/stok/opname");
  revalidatePath(`/stok/opname/${parsed.data.opnameId}`);
  redirect(`/stok/opname/${parsed.data.opnameId}?posted=1`);
}

