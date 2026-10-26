"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import { stockAdjustmentSchema } from "./schema";

export type StockAdjustmentState = { error: string | null };

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
