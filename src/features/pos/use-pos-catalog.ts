"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";

import { getCatalogDb } from "@/lib/offline/catalog-db";
import { buildScopeKey, normalizeScope } from "@/lib/offline/catalog-schema";
import {
  hydrateCatalog,
  readCatalog,
  searchCachedProducts,
} from "@/lib/offline/catalog-store";

import { getPosCatalogAction } from "./actions";
import type { PosCustomer, PosProduct } from "./queries";

export type CatalogCacheStatus = "loading" | "ready" | "empty" | "error";

export type UsePosCatalogInput = {
  tenantId: string;
  outletId: string;
  tierId: string | null;
  defaultTierId: string | null;
  query: string;
  initialProducts: PosProduct[];
  initialCustomers: PosCustomer[];
};

export type UsePosCatalogResult = {
  products: PosProduct[];
  customers: PosCustomer[];
  results: PosProduct[];
  status: CatalogCacheStatus;
  isOffline: boolean;
  syncing: boolean;
  lastSyncedAt: string | null;
  error: string | null;
  sync: () => Promise<void>;
  /** Baca ulang cache (mis. setelah stok lokal dikurangi transaksi offline). */
  reload: () => Promise<void>;
};

const SEARCH_DEBOUNCE_MS = 80;

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

/**
 * Katalog kasir: hidrasi dari server ke Dexie, lalu pencarian dari cache lokal.
 * Server hanya dipanggil saat cache kosong/belum siap atau saat sinkron ulang.
 */
export function usePosCatalog(
  input: UsePosCatalogInput
): UsePosCatalogResult {
  const {
    tenantId,
    outletId,
    tierId,
    defaultTierId,
    query,
    initialProducts,
    initialCustomers,
  } = input;

  const scope = useMemo(
    () => normalizeScope({ tenantId, outletId, tierId }),
    [tenantId, outletId, tierId]
  );
  const scopeKey = buildScopeKey(scope);

  const [products, setProducts] = useState<PosProduct[]>(initialProducts);
  const [customers, setCustomers] = useState<PosCustomer[]>(initialCustomers);
  const [results, setResults] = useState<PosProduct[]>(initialProducts);
  const [loadedScopeKey, setLoadedScopeKey] = useState<string | null>(scopeKey);
  const [loadedTenantId, setLoadedTenantId] = useState<string | null>(tenantId);
  const [status, setStatus] = useState<CatalogCacheStatus>("loading");
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [syncing, setSyncing] = useState(false);
  const isOffline = !useSyncExternalStore(
    subscribeOnline,
    getOnlineSnapshot,
    getOnlineServerSnapshot
  );
  const wasOfflineRef = useRef(false);

  const activeScopeKeyRef = useRef(scopeKey);
  const syncingScopesRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    activeScopeKeyRef.current = scopeKey;
  }, [scopeKey]);

  const applyRead = useCallback(
    (
      read: NonNullable<Awaited<ReturnType<typeof readCatalog>>>,
      key: string
    ) => {
      setProducts(read.products);
      setCustomers(read.customers);
      setLastSyncedAt(read.meta.lastSyncedAt);
      setLoadedScopeKey(key);
      setLoadedTenantId(read.meta.tenantId);
      setStatus(read.products.length > 0 ? "ready" : "empty");
    },
    []
  );

  const runSync = useCallback(async (): Promise<void> => {
    const targetScope = scope;
    const targetKey = scopeKey;
    if (syncingScopesRef.current.has(targetKey)) return;

    syncingScopesRef.current.add(targetKey);
    setSyncing(true);
    setError(null);

    try {
      const result = await getPosCatalogAction(targetScope.tierId);
      if (activeScopeKeyRef.current !== targetKey) return;

      if (result.error) {
        setError(result.error);
        setStatus((prev) => (prev === "loading" ? "empty" : prev));
        return;
      }
      if (
        result.tenantId !== targetScope.tenantId ||
        result.outletId !== targetScope.outletId
      ) {
        setError("Sesi kasir berubah. Muat ulang halaman kasir.");
        return;
      }

      const database = getCatalogDb();
      await hydrateCatalog(database, targetScope, {
        products: result.products,
        customers: result.customers,
        priceBreaks: result.priceBreaks,
      });
      if (activeScopeKeyRef.current !== targetKey) return;

      const read = await readCatalog(database, targetScope);
      if (activeScopeKeyRef.current !== targetKey) return;

      if (read) {
        applyRead(read, targetKey);
      } else {
        setLastSyncedAt(new Date().toISOString());
      }
    } catch {
      if (activeScopeKeyRef.current === targetKey) {
        setError("Gagal memperbarui cache. Data lokal tetap dipakai.");
        setStatus((prev) => (prev === "loading" ? "empty" : prev));
      }
    } finally {
      syncingScopesRef.current.delete(targetKey);
      setSyncing(syncingScopesRef.current.size > 0);
    }
  }, [applyRead, scope, scopeKey]);

  const reload = useCallback(async (): Promise<void> => {
    const targetScope = scope;
    const targetKey = scopeKey;
    const read = await readCatalog(getCatalogDb(), targetScope);
    if (activeScopeKeyRef.current !== targetKey || !read) return;
    applyRead(read, targetKey);
  }, [applyRead, scope, scopeKey]);

  // Muat cache scope aktif; kalau belum ada, hidrasi dari data SSR lalu
  // revalidasi ke server saat online.
  useEffect(() => {
    let cancelled = false;
    const database = getCatalogDb();

    async function load() {
      const cached = await readCatalog(database, scope);
      if (cancelled) return;
      setError(null);
      if (cached) {
        applyRead(cached, scopeKey);
      } else if (tierId === defaultTierId && initialProducts.length > 0) {
        await hydrateCatalog(database, scope, {
          products: initialProducts,
          customers: initialCustomers,
          priceBreaks: [],
        });
        if (cancelled) return;

        const read = await readCatalog(database, scope);
        if (cancelled) return;
        if (read) {
          applyRead(read, scopeKey);
        }
      } else {
        setProducts([]);
        setResults([]);
        setCustomers(initialCustomers);
        setLoadedScopeKey(scopeKey);
        setLoadedTenantId(tenantId);
        setStatus("loading");
      }

      if (!cancelled && navigator.onLine) {
        void runSync();
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [
    applyRead,
    defaultTierId,
    initialCustomers,
    initialProducts,
    runSync,
    scope,
    scopeKey,
    tenantId,
    tierId,
  ]);

  // Pencarian lokal dari Dexie. Debounce kecil supaya tetap terasa instan.
  useEffect(() => {
    let cancelled = false;
    const normalized = query.trim();
    const visible = loadedScopeKey === scopeKey ? products : [];

    if (!normalized) {
      return;
    }

    const timer = window.setTimeout(() => {
      void searchCachedProducts(getCatalogDb(), scope, normalized)
        .then((rows) => {
          if (!cancelled) setResults(rows);
        })
        .catch(() => {
          if (!cancelled) setResults(visible);
        });

      // Fallback ke server hanya kalau cache belum terisi.
      if (visible.length === 0 && navigator.onLine) {
        void runSync();
      }
    }, SEARCH_DEBOUNCE_MS);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [loadedScopeKey, products, query, runSync, scope, scopeKey]);

  // Sinkron ulang sekali setelah koneksi pulih.
  useEffect(() => {
    if (!isOffline) {
      if (wasOfflineRef.current) {
        wasOfflineRef.current = false;
        void runSync();
      }
      return;
    }
    wasOfflineRef.current = true;
  }, [isOffline, runSync]);

  const visibleProducts = loadedScopeKey === scopeKey ? products : [];
  const visibleResults = loadedScopeKey === scopeKey ? results : [];
  const visibleCustomers =
    loadedTenantId === tenantId ? customers : initialCustomers;
  const hasQuery = query.trim().length > 0;

  return {
    products: visibleProducts,
    customers: visibleCustomers,
    results: hasQuery ? visibleResults : visibleProducts,
    status: loadedScopeKey === scopeKey ? status : "loading",
    isOffline,
    syncing,
    lastSyncedAt: loadedScopeKey === scopeKey ? lastSyncedAt : null,
    error,
    sync: runSync,
    reload,
  };
}
