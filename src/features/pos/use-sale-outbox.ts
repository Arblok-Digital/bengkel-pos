"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";

import { getCatalogDb } from "@/lib/offline/catalog-db";
import {
  buildLocalInvoiceNo,
  nextLocalSeq,
  readDeviceId,
  type OutboxSale,
  type OutboxSalePayload,
} from "@/lib/offline/outbox-schema";
import {
  claimNextOutboxSale,
  countOutbox,
  enqueueSale,
  markOutboxRetry,
  markOutboxSynced,
  pruneOutbox,
  resetStuckSyncing,
} from "@/lib/offline/outbox-store";

import { syncOfflineSaleAction, type SyncSaleOutcome } from "./outbox-actions";

export type SaleOutbox = {
  pending: number;
  needsReview: number;
  failed: number;
  syncing: boolean;
  error: string | null;
  isOffline: boolean;
  enqueue: (
    payload: OutboxSalePayload,
    tierId: string | null
  ) => Promise<OutboxSale>;
  flush: () => Promise<void>;
  refresh: () => Promise<void>;
};

function subscribeOnline(callback: () => void): () => void {
  window.addEventListener("online", callback);
  window.addEventListener("offline", callback);
  return () => {
    window.removeEventListener("online", callback);
    window.removeEventListener("offline", callback);
  };
}

function getOnlineSnapshot(): boolean {
  return typeof navigator === "undefined" ? true : navigator.onLine;
}

function getOnlineServerSnapshot(): boolean {
  return true;
}

async function deliver(row: OutboxSale): Promise<SyncSaleOutcome> {
  return syncOfflineSaleAction({
    ...row.payload,
    localInvoiceNo: row.localInvoiceNo,
  });
}

async function applyOutcome(
  db: ReturnType<typeof getCatalogDb>,
  row: OutboxSale,
  outcome: SyncSaleOutcome
): Promise<void> {
  if (outcome.ok) {
    await markOutboxSynced(db, row.clientUuid, {
      saleId: outcome.saleId,
      invoiceNo: outcome.invoiceNo,
      status: outcome.status,
      needsReviewReason: outcome.needsReviewReason,
    });
    return;
  }

  await markOutboxRetry(
    db,
    row.clientUuid,
    outcome.error ?? "Gagal mengirim transaksi."
  );
}

/**
 * Antrean transaksi offline: simpan ke Dexie, kirim berurutan saat online,
 * dan biarkan pemilik menyelesaikan transaksi yang masuk `needs_review`.
 */
export function useSaleOutbox(input: {
  tenantId: string;
  onSynced?: () => void;
}): SaleOutbox {
  const { tenantId, onSynced } = input;
  const [counts, setCounts] = useState({
    pending: 0,
    needsReview: 0,
    failed: 0,
  });
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isOffline = !useSyncExternalStore(
    subscribeOnline,
    getOnlineSnapshot,
    getOnlineServerSnapshot
  );

  const runningRef = useRef(false);
  const onSyncedRef = useRef(onSynced);

  useEffect(() => {
    onSyncedRef.current = onSynced;
  }, [onSynced]);

  const refresh = useCallback(async (): Promise<void> => {
    setCounts(await countOutbox(getCatalogDb(), tenantId));
  }, [tenantId]);

  const flush = useCallback(async (): Promise<void> => {
    if (runningRef.current || !navigator.onLine) return;

    runningRef.current = true;
    setSyncing(true);
    setError(null);

    try {
      const db = getCatalogDb();
      let synced = false;

      for (;;) {
        const row = await claimNextOutboxSale(db, tenantId);
        if (!row) break;

        const outcome = await deliver(row);
        await applyOutcome(db, row, outcome);

        if (!outcome.ok) {
          setError(outcome.error);
          break;
        }
        synced = true;
      }

      await pruneOutbox(db, tenantId);
      if (synced) onSyncedRef.current?.();
    } finally {
      runningRef.current = false;
      setSyncing(false);
      await refresh();
    }
  }, [refresh, tenantId]);

  const enqueue = useCallback(
    async (
      payload: OutboxSalePayload,
      tierId: string | null
    ): Promise<OutboxSale> => {
      const db = getCatalogDb();
      const row = await enqueueSale(db, {
        payload,
        tierId,
        localInvoiceNo: buildLocalInvoiceNo(readDeviceId(), nextLocalSeq()),
      });
      setCounts(await countOutbox(db, tenantId));
      return row;
    },
    [tenantId]
  );

  // Saat halaman dibuka: pulihkan baris "syncing" yang tertinggal lalu kirim.
  useEffect(() => {
    let cancelled = false;

    async function boot() {
      const db = getCatalogDb();
      await resetStuckSyncing(db, tenantId);
      if (cancelled) return;
      setCounts(await countOutbox(db, tenantId));
      if (!cancelled && navigator.onLine) {
        void flush();
      }
    }

    void boot();
    return () => {
      cancelled = true;
    };
  }, [flush, tenantId]);

  // Koneksi pulih → langsung kirim sisa antrean.
  useEffect(() => {
    if (isOffline) return;
    void flush();
  }, [flush, isOffline]);

  return {
    pending: counts.pending,
    needsReview: counts.needsReview,
    failed: counts.failed,
    syncing,
    error,
    isOffline,
    enqueue,
    flush,
    refresh,
  };
}
