"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import type { Json } from "@/lib/supabase/types";
import { createSaleSchema } from "./schema";

export type CreateSaleState = {
  error: string | null;
  success: {
    saleId: string;
    invoiceNo: string;
    total: number;
    paidAmount: number;
    changeAmount: number;
    status: string;
  } | null;
};

const initialState: CreateSaleState = { error: null, success: null };

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

export async function createSaleAction(
  _prev: CreateSaleState,
  formData: FormData
): Promise<CreateSaleState> {
  const raw = str(formData, "payload");
  let payload: unknown;
  try {
    payload = JSON.parse(raw);
  } catch {
    return { ...initialState, error: "Data keranjang tidak valid." };
  }

  const parsed = createSaleSchema.safeParse(payload);
  if (!parsed.success) {
    return {
      ...initialState,
      error: parsed.error.issues[0]?.message ?? "Isian transaksi tidak valid.",
    };
  }

  const data = parsed.data;
  const supabase = await createClient();
  const { data: result, error } = await supabase.rpc("create_sale", {
    p_client_uuid: data.clientUuid,
    p_tenant_id: data.tenantId,
    p_outlet_id: data.outletId,
    p_customer_id: data.customerId ?? null,
    p_items: data.items.map((item) => ({
      product_id: item.productId,
      unit_id: item.unitId,
      qty: item.qty,
      unit_price: item.unitPrice,
      discount: item.discount,
      note: item.note ?? null,
    })) as unknown as Json,
    p_payments: data.payments.map((payment) => ({
      method: payment.method,
      amount: payment.amount,
      reference: payment.reference ?? null,
    })) as unknown as Json,
    p_shift_id: data.shiftId ?? null,
    p_note: data.note ?? null,
    p_vehicle_id: null,
    p_work_order_id: null,
  });

  if (error) {
    const known = [
      "berhak",
      "Stok",
      "Harga",
      "Satuan",
      "Shift",
      "limit kredit",
      "Pembayaran",
      "Minimal",
      "client_uuid",
      "Pelanggan",
      "Outlet",
      "Produk",
      "Qty",
      "Diskon",
      "Metode",
    ].some((fragment) => error.message.toLowerCase().includes(fragment.toLowerCase()));
    return {
      ...initialState,
      error: known ? error.message : "Gagal menyimpan transaksi.",
    };
  }

  const row = (result ?? {}) as Record<string, Json | undefined>;
  revalidatePath("/kasir");
  revalidatePath("/stok");

  return {
    error: null,
    success: {
      saleId: String(row.sale_id ?? ""),
      invoiceNo: String(row.invoice_no ?? ""),
      total: Number(row.total ?? 0),
      paidAmount: Number(row.paid_amount ?? 0),
      changeAmount: Number(row.change_amount ?? 0),
      status: String(row.status ?? ""),
    },
  };
}
