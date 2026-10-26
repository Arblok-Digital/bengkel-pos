"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import { closeShiftSchema, openShiftSchema } from "./schema";

export type ShiftActionState = { error: string | null };

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

function knownMessage(message: string): boolean {
  return [
    "berhak",
    "shift terbuka",
    "sudah ditutup",
    "tidak boleh negatif",
    "client_uuid",
    "tidak ditemukan",
  ].some((fragment) => message.toLowerCase().includes(fragment));
}

export async function openShiftAction(
  _prev: ShiftActionState,
  formData: FormData
): Promise<ShiftActionState> {
  const parsed = openShiftSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    outletId: str(formData, "outletId"),
    clientUuid: str(formData, "clientUuid"),
    openingCash: str(formData, "openingCash"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian buka kasir tidak valid.",
    };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("open_cash_shift", {
    p_tenant_id: parsed.data.tenantId,
    p_outlet_id: parsed.data.outletId,
    p_opening_cash: parsed.data.openingCash,
    p_client_uuid: parsed.data.clientUuid,
  });

  if (error) {
    return {
      error: knownMessage(error.message)
        ? error.message
        : "Gagal membuka shift kasir.",
    };
  }

  revalidatePath("/kasir");
  redirect("/kasir?opened=1");
}

export async function closeShiftAction(
  _prev: ShiftActionState,
  formData: FormData
): Promise<ShiftActionState> {
  const parsed = closeShiftSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    shiftId: str(formData, "shiftId"),
    clientUuid: str(formData, "clientUuid"),
    closingCashCounted: str(formData, "closingCashCounted"),
    note: str(formData, "note"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian tutup kasir tidak valid.",
    };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("close_cash_shift", {
    p_shift_id: parsed.data.shiftId,
    p_closing_cash_counted: parsed.data.closingCashCounted,
    p_note: parsed.data.note || null,
    p_client_uuid: parsed.data.clientUuid,
  });

  if (error) {
    return {
      error: knownMessage(error.message)
        ? error.message
        : "Gagal menutup shift kasir.",
    };
  }

  revalidatePath("/kasir");
  redirect("/kasir?closed=1");
}
