// Skema antrean transaksi offline (outbox) di Dexie.
//
// Aturan:
// - Satu baris = satu transaksi kasir yang belum/tidak perlu dikirim ulang.
// - `clientUuid` dibuat saat transaksi terjadi dan dipakai server untuk
//   idempotensi, jadi kirim ulang tidak pernah membuat penjualan ganda.
// - `localInvoiceNo` (TMP-<device>-<seq>) hanya nomor sementara di struk offline;
//   nomor resmi datang dari server setelah sinkron.
// - Tidak ada HPP di sini: payload hanya berisi yang dikirim kasir ke create_sale.

export type OutboxState =
  | "pending"
  | "syncing"
  | "needs_review"
  | "done"
  | "failed";

export type OutboxItemPayload = {
  productId: string;
  unitId: string;
  qty: number;
  unitPrice: number;
  discount: number;
  note?: string;
};

export type OutboxPaymentPayload = {
  method: "tunai" | "transfer" | "qris" | "debit" | "kredit_tempo";
  amount: number;
  reference?: string;
};

export type OutboxSalePayload = {
  clientUuid: string;
  tenantId: string;
  outletId: string;
  shiftId?: string;
  customerId?: string;
  note?: string;
  items: OutboxItemPayload[];
  payments: OutboxPaymentPayload[];
};

export type OutboxSale = {
  clientUuid: string;
  tenantId: string;
  outletId: string;
  shiftId: string | null;
  tierId: string | null;
  localInvoiceNo: string;
  payload: OutboxSalePayload;
  createdAt: string;
  updatedAt: string;
  state: OutboxState;
  attempts: number;
  lastError: string | null;
  saleId: string | null;
  invoiceNo: string | null;
  needsReviewReason: string | null;
  syncedAt: string | null;
};

export type OutboxSyncResult = {
  saleId: string;
  invoiceNo: string;
  status: string;
  needsReviewReason: string | null;
};

/** Batas percobaan otomatis; setelah itu kasir harus menekan "Kirim antrean". */
export const OUTBOX_MAX_ATTEMPTS = 5;

const DEVICE_STORAGE_KEY = "bengkel-pos-device-id";

export function buildLocalInvoiceNo(deviceId: string, seq: number): string {
  const device = deviceId.replace(/[^a-zA-Z0-9]/g, "").slice(0, 4).toUpperCase();
  return `TMP-${device || "POS"}-${String(seq).padStart(4, "0")}`;
}

/** ID perangkat stabil untuk awalan nomor sementara. */
export function readDeviceId(): string {
  if (typeof window === "undefined") return "POS";

  try {
    const existing = window.localStorage.getItem(DEVICE_STORAGE_KEY);
    if (existing) return existing;
    const created = crypto.randomUUID();
    window.localStorage.setItem(DEVICE_STORAGE_KEY, created);
    return created;
  } catch {
    // localStorage diblokir: nomor sementara tetap unik per sesi.
    return "POS";
  }
}

/**
 * Nomor urut lokal per perangkat. Disimpan di localStorage supaya nomor
 * sementara tidak berulang setelah halaman dimuat ulang.
 */
export function nextLocalSeq(): number {
  if (typeof window === "undefined") return 1;

  try {
    const raw = window.localStorage.getItem("bengkel-pos-outbox-seq");
    const current = Number.parseInt(raw ?? "0", 10);
    const next = Number.isFinite(current) ? current + 1 : 1;
    window.localStorage.setItem("bengkel-pos-outbox-seq", String(next));
    return next;
  } catch {
    return Date.now() % 1_000_000;
  }
}

export function isOpenState(state: OutboxState): boolean {
  return state === "pending" || state === "syncing" || state === "failed";
}
