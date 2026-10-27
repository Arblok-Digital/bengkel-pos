"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import type { Json } from "@/lib/supabase/types";
import {
  getPosCustomers,
  getPosPriceBreaks,
  getPosProducts,
  getPosShift,
  type PosCustomer,
  type PosPriceBreak,
  type PosProduct,
} from "./queries";
import { createSaleSchema, priceRequestSchema } from "./schema";

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

export type PriceResult = { price: number | null; error: string | null };

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

/** Harga final dari server untuk satu baris keranjang (tier + grosir). */
export async function resolveSalePriceAction(input: {
  productId: string;
  unitId: string;
  qty: number;
  tierId: string | null;
}): Promise<PriceResult> {
  const parsed = priceRequestSchema.safeParse(input);
  if (!parsed.success) {
    return { price: null, error: "Permintaan harga tidak valid." };
  }

  const context = await getPosShift();
  if (!context) {
    return { price: null, error: "Sesi tidak valid." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("resolve_price", {
    p_tenant_id: context.tenantId,
    p_product_id: parsed.data.productId,
    p_unit_id: parsed.data.unitId,
    p_tier_id: parsed.data.tierId ?? null,
    p_qty: parsed.data.qty,
  });

  if (error || data === null) {
    return { price: null, error: error?.message ?? "Harga tidak ditemukan." };
  }

  return { price: Number(data), error: null };
}

/** Snapshot katalog untuk hidrasi cache Dexie di browser. Tanpa HPP. */
export type PosCatalogSnapshotResult = {
  tenantId: string;
  outletId: string;
  tierId: string | null;
  products: PosProduct[];
  customers: PosCustomer[];
  priceBreaks: PosPriceBreak[];
  error: string | null;
};

/** Katalog + pelanggan + harga grosir untuk cache lokal saat tier berubah. */
export async function getPosCatalogAction(
  tierId: string | null
): Promise<PosCatalogSnapshotResult> {
  const context = await getPosShift();
  if (!context?.shift) {
    return {
      tenantId: context?.tenantId ?? "",
      outletId: "",
      tierId,
      products: [],
      customers: [],
      priceBreaks: [],
      error: "Shift belum dibuka.",
    };
  }

  const [products, customers, priceBreaks] = await Promise.all([
    getPosProducts(context.tenantId, context.shift.outletId, tierId),
    getPosCustomers(context.tenantId),
    getPosPriceBreaks(context.tenantId),
  ]);

  return {
    tenantId: context.tenantId,
    outletId: context.shift.outletId,
    tierId,
    products,
    customers,
    priceBreaks,
    error: null,
  };
}
