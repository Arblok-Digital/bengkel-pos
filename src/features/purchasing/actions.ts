"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import type { Json } from "@/lib/supabase/types";
import { createPurchaseOrderSchema } from "./schema";

export type PurchaseOrderActionState = {
  error: string | null;
  success: {
    purchaseOrderId: string;
    poNo: string;
    total: number;
    status: string;
    idempotent: boolean;
  } | null;
};

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

function parseJsonArray(formData: FormData, key: string): unknown[] {
  const raw = str(formData, key);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed;
  } catch {
    // ignored
  }
  return [];
}

const initialState: PurchaseOrderActionState = {
  error: null,
  success: null,
};

export async function createPurchaseOrderAction(
  _prev: PurchaseOrderActionState,
  formData: FormData
): Promise<PurchaseOrderActionState> {
  const tenantId = str(formData, "tenantId");
  const outletId = str(formData, "outletId");
  const supplierId = str(formData, "supplierId");
  const clientUuid = str(formData, "clientUuid");
  const note = str(formData, "note") || null;
  const items = parseJsonArray(formData, "items");

  const parsed = createPurchaseOrderSchema.safeParse({
    tenantId,
    outletId,
    supplierId,
    clientUuid,
    note,
    items,
  });

  if (!parsed.success) {
    return {
      ...initialState,
      error: parsed.error.issues[0]?.message ?? "Isian PO tidak valid.",
    };
  }

  const data = parsed.data;
  const supabase = await createClient();
  const { data: result, error } = await supabase.rpc("create_purchase_order", {
    p_client_uuid: data.clientUuid,
    p_tenant_id: data.tenantId,
    p_outlet_id: data.outletId,
    p_supplier_id: data.supplierId,
    p_items: data.items.map((item) => ({
      product_id: item.productId,
      unit_id: item.unitId,
      qty: item.qty,
      unit_price: item.unitPrice,
      note: item.note ?? null,
    })) as unknown as Json,
    p_note: data.note ?? null,
  });

  if (error) {
    return {
      ...initialState,
      error: error.message.includes("berhak")
        ? "Hanya owner/admin yang boleh membuat PO."
        : error.message.includes("stok")
          ? "Stok tidak mencukupi."
          : "Gagal membuat PO.",
    };
  }

  const row = (result ?? {}) as Record<string, Json | undefined>;
  revalidatePath("/pembelian");
  revalidatePath(`/pembelian/${String(row.purchase_order_id ?? "")}`);

  return {
    ...initialState,
    success: {
      purchaseOrderId: String(row.purchase_order_id ?? ""),
      poNo: String(row.po_no ?? ""),
      total: Number(row.total ?? 0),
      status: String(row.status ?? ""),
      idempotent: Boolean(row.idempotent),
    },
  };
}
