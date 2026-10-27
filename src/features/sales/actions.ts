"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import type { Json } from "@/lib/supabase/types";
import { formatRupiah } from "@/lib/money";
import { receiptSettingsSchema, resolveSaleReviewSchema, saleReturnSchema, voidSaleSchema } from "./schema";

export type ReceiptSettingsState = {
  error: string | null;
  success: string | null;
};

export type SaleMutationState = {
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

function knownSaleError(message: string): boolean {
  return [
    "berhak",
    "wajib",
    "sudah",
    "retur",
    "tidak ditemukan",
    "melebihi",
    "void",
    "client_uuid",
    "stok",
    "review",
  ].some((fragment) => message.toLowerCase().includes(fragment));
}

export async function voidSaleAction(
  _prev: SaleMutationState,
  formData: FormData
): Promise<SaleMutationState> {
  const parsed = voidSaleSchema.safeParse({
    saleId: str(formData, "saleId"),
    reason: str(formData, "reason"),
    clientUuid: str(formData, "clientUuid"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian void tidak valid.",
      success: null,
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("void_sale", {
    p_sale_id: parsed.data.saleId,
    p_reason: parsed.data.reason,
    p_client_uuid: parsed.data.clientUuid,
  });

  if (error) {
    return {
      error: knownSaleError(error.message)
        ? error.message
        : "Gagal void penjualan.",
      success: null,
    };
  }

  const row = (data ?? {}) as Record<string, Json | undefined>;
  revalidatePath("/penjualan");
  revalidatePath(`/penjualan/${parsed.data.saleId}`);
  revalidatePath("/stok");
  revalidatePath("/kasir");

  return {
    error: null,
    success: `Penjualan ${String(row.invoice_no ?? "")} di-void.`,
  };
}

export async function returnSaleAction(
  _prev: SaleMutationState,
  formData: FormData
): Promise<SaleMutationState> {
  const items: { saleItemId: string; qty: number }[] = [];
  for (const [key, value] of formData.entries()) {
    if (!key.startsWith("ret_") || typeof value !== "string") continue;
    const qty = Number(value);
    if (!Number.isFinite(qty) || qty <= 0) continue;
    items.push({ saleItemId: key.slice(4), qty });
  }

  const parsed = saleReturnSchema.safeParse({
    saleId: str(formData, "saleId"),
    reason: str(formData, "reason"),
    clientUuid: str(formData, "clientUuid"),
    items,
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian retur tidak valid.",
      success: null,
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_sale_return", {
    p_sale_id: parsed.data.saleId,
    p_items: parsed.data.items.map((item) => ({
      sale_item_id: item.saleItemId,
      qty: item.qty,
    })) as unknown as Json,
    p_reason: parsed.data.reason,
    p_client_uuid: parsed.data.clientUuid,
  });

  if (error) {
    return {
      error: knownSaleError(error.message)
        ? error.message
        : "Gagal menyimpan retur.",
      success: null,
    };
  }

  const row = (data ?? {}) as Record<string, Json | undefined>;
  revalidatePath("/penjualan");
  revalidatePath(`/penjualan/${parsed.data.saleId}`);
  revalidatePath("/stok");
  revalidatePath("/kasir");

  return {
    error: null,
    success: `Retur tersimpan: ${formatRupiah(Number(row.total ?? 0))}.`,
  };
}

export async function resolveSaleReviewAction(
  _prev: SaleMutationState,
  formData: FormData
): Promise<SaleMutationState> {
  const parsed = resolveSaleReviewSchema.safeParse({
    saleId: str(formData, "saleId"),
    action: str(formData, "action"),
    reason: str(formData, "reason") || undefined,
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian review tidak valid.",
      success: null,
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("resolve_sale_review", {
    p_sale_id: parsed.data.saleId,
    p_action: parsed.data.action,
    p_reason: parsed.data.reason ?? null,
  });

  if (error) {
    return {
      error: knownSaleError(error.message)
        ? error.message
        : "Gagal menyelesaikan transaksi review.",
      success: null,
    };
  }

  const row = (data ?? {}) as Record<string, Json | undefined>;
  revalidatePath("/penjualan");
  revalidatePath(`/penjualan/${parsed.data.saleId}`);
  revalidatePath("/stok");
  revalidatePath("/kasir");

  return {
    error: null,
    success:
      parsed.data.action === "accept"
        ? `Transaksi ${String(row.invoice_no ?? "")} disetujui dan stok dipotong.`
        : `Transaksi ${String(row.invoice_no ?? "")} dibatalkan.`,
  };
}
