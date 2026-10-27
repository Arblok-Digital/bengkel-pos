import type { OfflineCatalogDb } from "./catalog-db";
import {
  isOpenState,
  OUTBOX_MAX_ATTEMPTS,
  type OutboxSale,
  type OutboxSalePayload,
  type OutboxSyncResult,
} from "./outbox-schema";

export type EnqueueSaleInput = {
  payload: OutboxSalePayload;
  localInvoiceNo: string;
  tierId: string | null;
  now?: Date;
};

export type OutboxCounts = {
  pending: number;
  needsReview: number;
  failed: number;
};

const RETENTION_DAYS = 7;

/**
 * Simpan transaksi ke antrean lokal. Idempoten terhadap `clientUuid`: menekan
 * tombol bayar dua kali tidak membuat dua baris antrean.
 */
export async function enqueueSale(
  db: OfflineCatalogDb,
  input: EnqueueSaleInput
): Promise<OutboxSale> {
  const nowIso = (input.now ?? new Date()).toISOString();
  const existing = await db.outbox.get(input.payload.clientUuid);
  if (existing) return existing;

  const row: OutboxSale = {
    clientUuid: input.payload.clientUuid,
    tenantId: input.payload.tenantId,
    outletId: input.payload.outletId,
    shiftId: input.payload.shiftId ?? null,
    tierId: input.tierId,
    localInvoiceNo: input.localInvoiceNo,
    payload: input.payload,
    createdAt: nowIso,
    updatedAt: nowIso,
    state: "pending",
    attempts: 0,
    lastError: null,
    saleId: null,
    invoiceNo: null,
    needsReviewReason: null,
    syncedAt: null,
  };

  await db.outbox.put(row);
  return row;
}

export async function listOutbox(
  db: OfflineCatalogDb,
  tenantId: string
): Promise<OutboxSale[]> {
  const rows = await db.outbox.where("tenantId").equals(tenantId).toArray();
  return rows.sort(
    (a, b) => a.createdAt.localeCompare(b.createdAt) || a.clientUuid.localeCompare(b.clientUuid)
  );
}

export async function countOutbox(
  db: OfflineCatalogDb,
  tenantId: string
): Promise<OutboxCounts> {
  const rows = await db.outbox.where("tenantId").equals(tenantId).toArray();
  return rows.reduce<OutboxCounts>(
    (acc, row) => {
      if (row.state === "needs_review") acc.needsReview += 1;
      else if (row.state === "failed") acc.failed += 1;
      else if (row.state === "pending" || row.state === "syncing") {
        acc.pending += 1;
      }
      return acc;
    },
    { pending: 0, needsReview: 0, failed: 0 }
  );
}

/** Ambil satu baris untuk dikirim dan tandai `syncing` (atomik). */
async function claim(
  db: OfflineCatalogDb,
  row: OutboxSale,
  now: Date
): Promise<OutboxSale> {
  const updated: OutboxSale = {
    ...row,
    state: "syncing",
    updatedAt: now.toISOString(),
  };
  await db.outbox.put(updated);
  return updated;
}

export async function claimNextOutboxSale(
  db: OfflineCatalogDb,
  tenantId: string,
  now: Date = new Date()
): Promise<OutboxSale | null> {
  return db.transaction("rw", db.outbox, async () => {
    const rows = await db.outbox
      .where("[tenantId+state]")
      .equals([tenantId, "pending"])
      .toArray();
    if (rows.length === 0) return null;

    rows.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    return claim(db, rows[0], now);
  });
}

export async function markOutboxSynced(
  db: OfflineCatalogDb,
  clientUuid: string,
  result: OutboxSyncResult,
  now: Date = new Date()
): Promise<void> {
  const row = await db.outbox.get(clientUuid);
  if (!row) return;

  await db.outbox.put({
    ...row,
    state: result.needsReviewReason ? "needs_review" : "done",
    attempts: row.attempts + 1,
    lastError: null,
    saleId: result.saleId,
    invoiceNo: result.invoiceNo,
    needsReviewReason: result.needsReviewReason,
    syncedAt: now.toISOString(),
    updatedAt: now.toISOString(),
  });
}

/**
 * Gagal kirim: tetap di antrean selama percobaan belum habis. Setelah
 * `OUTBOX_MAX_ATTEMPTS`, status jadi `failed` dan kasir bisa mengirim manual.
 */
export async function markOutboxRetry(
  db: OfflineCatalogDb,
  clientUuid: string,
  error: string,
  now: Date = new Date()
): Promise<void> {
  const row = await db.outbox.get(clientUuid);
  if (!row) return;

  const attempts = row.attempts + 1;
  await db.outbox.put({
    ...row,
    state: attempts >= OUTBOX_MAX_ATTEMPTS ? "failed" : "pending",
    attempts,
    lastError: error,
    updatedAt: now.toISOString(),
  });
}

/** Baris `syncing` yang tertinggal (tab ditutup saat kirim) boleh dicoba lagi. */
export async function resetStuckSyncing(
  db: OfflineCatalogDb,
  tenantId: string,
  now: Date = new Date()
): Promise<void> {
  const rows = await db.outbox
    .where("[tenantId+state]")
    .equals([tenantId, "syncing"])
    .toArray();

  await db.outbox.bulkPut(
    rows.map((row) => ({
      ...row,
      state: "pending" as const,
      updatedAt: now.toISOString(),
    }))
  );
}

/** Baris yang sudah diterima server tidak perlu disimpan selamanya. */
export async function pruneOutbox(
  db: OfflineCatalogDb,
  tenantId: string,
  now: Date = new Date()
): Promise<void> {
  const cutoff = new Date(
    now.getTime() - RETENTION_DAYS * 24 * 60 * 60 * 1000
  ).toISOString();

  const rows = await db.outbox.where("tenantId").equals(tenantId).toArray();
  const stale = rows.filter(
    (row) => row.state === "done" && row.createdAt < cutoff
  );
  if (stale.length === 0) return;

  await db.outbox.bulkDelete(stale.map((row) => row.clientUuid));
}

export async function removeOutboxSale(
  db: OfflineCatalogDb,
  clientUuid: string
): Promise<void> {
  await db.outbox.delete(clientUuid);
}

/** Dipakai tes dan pembersihan manual; jangan dipanggil saat logout. */
export async function clearOutbox(db: OfflineCatalogDb): Promise<void> {
  await db.outbox.clear();
}

export function hasOpenSales(rows: readonly OutboxSale[]): boolean {
  return rows.some((row) => isOpenState(row.state));
}
