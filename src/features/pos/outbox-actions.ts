"use server";

import { revalidatePath } from "next/cache";

import type { Json } from "@/lib/supabase/types";
import { createClient } from "@/lib/supabase/server";

import { syncSaleSchema } from "./schema";
import { saleErrorMessage } from "./sale-error";

export type SyncSaleOutcome = {
  ok: boolean;
  saleId: string;
  invoiceNo: string;
  status: string;
  needsReviewReason: string | null;
  total: number;
  paidAmount: number;
  changeAmount: number;
  error: string | null;
};

function emptyOutcome(error: string | null): SyncSaleOutcome {
  return {
    ok: false,
    saleId: "",
    invoiceNo: "",
    status: "",
    needsReviewReason: null,
    total: 0,
    paidAmount: 0,
    changeAmount: 0,
    error,
  };
}

/**
 * Kirim satu transaksi dari outbox ke `sync_sale`.
 * Beda dengan `create_sale`: konflik stok/harga tidak membuang transaksi,
 * server menyimpannya sebagai `needs_review`.
 */
export async function syncOfflineSaleAction(
  input: unknown
): Promise<SyncSaleOutcome> {
  const parsed = syncSaleSchema.safeParse(input);
  if (!parsed.success) {
    return emptyOutcome(
      parsed.error.issues[0]?.message ?? "Data transaksi offline tidak valid."
    );
  }

  const data = parsed.data;
  const supabase = await createClient();
  const { data: result, error } = await supabase.rpc("sync_sale", {
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
    p_local_invoice_no: data.localInvoiceNo,
  });

  if (error) {
    return emptyOutcome(
      saleErrorMessage(error.message, "Gagal mengirim transaksi offline.")
    );
  }

  const row = (result ?? {}) as Record<string, Json | undefined>;
  revalidatePath("/kasir");
  revalidatePath("/stok");
  revalidatePath("/penjualan");

  return {
    ok: true,
    saleId: String(row.sale_id ?? ""),
    invoiceNo: String(row.invoice_no ?? ""),
    status: String(row.status ?? ""),
    needsReviewReason:
      typeof row.needs_review_reason === "string"
        ? row.needs_review_reason
        : null,
    total: Number(row.total ?? 0),
    paidAmount: Number(row.paid_amount ?? 0),
    changeAmount: Number(row.change_amount ?? 0),
    error: null,
  };
}
