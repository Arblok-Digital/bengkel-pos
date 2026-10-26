"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import type { Json } from "@/lib/supabase/types";
import { receiptSettingsSchema } from "./schema";

export type ReceiptSettingsState = {
  error: string | null;
  success: string | null;
};

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

export async function saveReceiptSettingsAction(
  _prev: ReceiptSettingsState,
  formData: FormData
): Promise<ReceiptSettingsState> {
  const parsed = receiptSettingsSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    storeName: str(formData, "storeName"),
    address: str(formData, "address"),
    phone: str(formData, "phone"),
    footer: str(formData, "footer"),
    logoUrl: str(formData, "logoUrl"),
    paperWidth: str(formData, "paperWidth"),
    hideTaxPercent: formData.get("hideTaxPercent") === "on",
    showMechanic: formData.get("showMechanic") === "on",
  });

  if (!parsed.success) {
    return {
      error:
        parsed.error.issues[0]?.message ?? "Isian pengaturan struk tidak valid.",
      success: null,
    };
  }

  const data = parsed.data;
  const supabase = await createClient();

  const { data: tenant } = await supabase
    .from("tenants")
    .select("settings")
    .eq("id", data.tenantId)
    .maybeSingle();

  if (!tenant) {
    return { error: "Tenant tidak ditemukan.", success: null };
  }

  const current =
    typeof tenant.settings === "object" &&
    tenant.settings !== null &&
    !Array.isArray(tenant.settings)
      ? (tenant.settings as Record<string, Json>)
      : {};

  const nextSettings = {
    ...current,
    receipt: {
      storeName: data.storeName || undefined,
      address: data.address ?? "",
      phone: data.phone ?? "",
      footer: data.footer ?? "",
      logoUrl: data.logoUrl ?? "",
      paperWidth: data.paperWidth,
      hideTaxPercent: data.hideTaxPercent,
      showMechanic: data.showMechanic,
    },
  };

  const { data: updated, error } = await supabase
    .from("tenants")
    .update({ settings: nextSettings })
    .eq("id", data.tenantId)
    .select("id")
    .maybeSingle();

  if (error || !updated) {
    return {
      error: "Gagal menyimpan pengaturan struk. Hanya pemilik/admin.",
      success: null,
    };
  }

  revalidatePath("/pengaturan");
  revalidatePath("/penjualan");
  return { error: null, success: "Pengaturan struk disimpan." };
}
