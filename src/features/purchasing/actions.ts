"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import type { Json } from "@/lib/supabase/types";
import {
  createPurchaseOrderSchema,
  createPayableSchema,
  receiveGoodsSchema,
  payPayableSchema,
} from "./schema";

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

export type ReceiveGoodsActionState = {
  error: string | null;
  success: {
    goodsReceiptId: string;
    grNo: string;
    total: number;
    status: string;
    idempotent: boolean;
  } | null;
};

export type CreatePayableActionState = {
  error: string | null;
  success: {
    payableId: string;
    clientUuid: string;
    amount: number;
    status: string;
    idempotent: boolean;
  } | null;
};

export type PayPayableActionState = {
  error: string | null;
  success: {
    paymentId: string;
    payableId: string;
    amount: number;
    totalPaid: number;
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

export async function receiveGoodsAction(
  _prev: ReceiveGoodsActionState,
  formData: FormData
): Promise<ReceiveGoodsActionState> {
  const tenantId = str(formData, "tenantId");
  const outletId = str(formData, "outletId");
  const supplierId = str(formData, "supplierId");
  const purchaseOrderId = str(formData, "purchaseOrderId") || null;
  const clientUuid = str(formData, "clientUuid");
  const note = str(formData, "note") || null;
  const items = parseJsonArray(formData, "items");

  const parsed = receiveGoodsSchema.safeParse({
    tenantId,
    outletId,
    supplierId,
    purchaseOrderId,
    clientUuid,
    note,
    items,
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian penerimaan tidak valid.",
      success: null,
    };
  }

  const data = parsed.data;
  const supabase = await createClient();
  const { data: result, error } = await supabase.rpc("receive_goods", {
    p_client_uuid: data.clientUuid,
    p_tenant_id: data.tenantId,
    p_outlet_id: data.outletId,
    p_supplier_id: data.supplierId,
    p_purchase_order_id: data.purchaseOrderId ?? null,
    p_items: data.items.map((item) => ({
      product_id: item.productId,
      unit_id: item.unitId,
      qty: item.qty,
      unit_cost: item.unitCost,
      purchaseOrderItemId: item.purchaseOrderItemId ?? null,
      note: item.note ?? null,
    })) as unknown as Json,
    p_note: data.note ?? null,
  });

  if (error) {
    return {
      error: error.message.includes("berhak")
        ? "Hanya owner/admin yang boleh menerima barang."
        : error.message.includes("PO")
          ? error.message
          : "Gagal menerima barang.",
      success: null,
    };
  }

  const row = (result ?? {}) as Record<string, Json | undefined>;
  revalidatePath("/penerimaan");
  revalidatePath("/pembelian");
  revalidatePath(`/penerimaan/${String(row.goods_receipt_id ?? "")}`);

  return {
    error: null,
    success: {
      goodsReceiptId: String(row.goods_receipt_id ?? ""),
      grNo: String(row.gr_no ?? ""),
      total: Number(row.total ?? 0),
      status: String(row.status ?? ""),
      idempotent: Boolean(row.idempotent),
    },
  };
}

export async function createPayableAction(
  _prev: CreatePayableActionState,
  formData: FormData
): Promise<CreatePayableActionState> {
  const tenantId = str(formData, "tenantId");
  const outletId = str(formData, "outletId");
  const supplierId = str(formData, "supplierId");
  const purchaseOrderId = str(formData, "purchaseOrderId") || null;
  const clientUuid = str(formData, "clientUuid");
  const amountRaw = str(formData, "amount");
  const dueDateRaw = str(formData, "dueDate");
  const note = str(formData, "note") || null;

  const amount = Number(amountRaw);
  const dueDate = dueDateRaw ? new Date(dueDateRaw).toISOString() : null;

  const parsed = createPayableSchema.safeParse({
    tenantId,
    outletId,
    supplierId,
    purchaseOrderId,
    clientUuid,
    amount,
    dueDate,
    note,
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian hutang tidak valid.",
      success: null,
    };
  }

  const data = parsed.data;
  const supabase = await createClient();
  const { data: result, error } = await supabase.rpc("create_payable", {
    p_client_uuid: data.clientUuid,
    p_tenant_id: data.tenantId,
    p_outlet_id: data.outletId,
    p_supplier_id: data.supplierId,
    p_purchase_order_id: data.purchaseOrderId ?? null,
    p_amount: data.amount,
    p_due_date: data.dueDate ?? null,
    p_note: data.note ?? null,
  });

  if (error) {
    return {
      error: error.message.includes("berhak")
        ? "Hanya owner/admin yang boleh mencatat hutang."
        : "Gagal mencatat hutang.",
      success: null,
    };
  }

  const row = (result ?? {}) as Record<string, Json | undefined>;
  revalidatePath("/hutang");

  return {
    error: null,
    success: {
      payableId: String(row.payable_id ?? ""),
      clientUuid: String(row.client_uuid ?? ""),
      amount: Number(row.amount ?? 0),
      status: String(row.status ?? ""),
      idempotent: Boolean(row.idempotent),
    },
  };
}

export async function payPayableAction(
  _prev: PayPayableActionState,
  formData: FormData
): Promise<PayPayableActionState> {
  const tenantId = str(formData, "tenantId");
  const payableId = str(formData, "payableId");
  const clientUuid = str(formData, "clientUuid");
  const amount = Number(str(formData, "amount"));
  const method = str(formData, "method");
  const reference = str(formData, "reference") || null;

  const parsed = payPayableSchema.safeParse({
    tenantId,
    payableId,
    clientUuid,
    amount,
    method,
    reference,
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian pembayaran tidak valid.",
      success: null,
    };
  }

  const data = parsed.data;
  const supabase = await createClient();
  const { data: result, error } = await supabase.rpc("pay_payable", {
    p_tenant_id: data.tenantId,
    p_payable_id: data.payableId,
    p_client_uuid: data.clientUuid,
    p_amount: data.amount,
    p_method: data.method,
    p_reference: data.reference ?? null,
  });

  if (error) {
    return {
      error: error.message.includes("berhak")
        ? "Hanya owner/admin yang boleh membayar hutang."
        : error.message.includes("lunas")
          ? "Hutang sudah lunas."
          : "Gagal membayar hutang.",
      success: null,
    };
  }

  const row = (result ?? {}) as Record<string, Json | undefined>;
  revalidatePath("/hutang");
  revalidatePath(`/hutang/${String(row.payable_id ?? "")}`);

  return {
    error: null,
    success: {
      paymentId: String(row.payment_id ?? ""),
      payableId: String(row.payable_id ?? ""),
      amount: Number(row.amount ?? 0),
      totalPaid: Number(row.total_paid ?? 0),
      status: String(row.status ?? ""),
      idempotent: Boolean(row.idempotent),
    },
  };
}
