"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useTransition,
} from "react";

import { Button } from "@/components/ui/button";
import {
  createSaleAction,
  getPosCatalogAction,
  resolveSalePriceAction,
  type CreateSaleState,
} from "@/features/pos/actions";
import type { PosCustomer, PosData, PosProduct } from "@/features/pos/queries";
import { formatRupiah, mulQty } from "@/lib/money";

type CartLine = {
  key: string;
  productId: string;
  name: string;
  unitId: string;
  unitName: string;
  factor: number;
  qty: number;
  unitPrice: number;
  discount: number;
  stockQty: number;
  trackStock: boolean;
  pricing: boolean;
  resolvedFor: string;
};

const initialState: CreateSaleState = { error: null, success: null };

function formatQty(value: number): string {
  return value.toLocaleString("id-ID", { maximumFractionDigits: 3 });
}

function lineGross(line: CartLine): number {
  return mulQty(line.qty, line.unitPrice);
}

function lineTotal(line: CartLine): number {
  return Math.max(0, lineGross(line) - line.discount);
}

function priceKey(unitId: string, qty: number, tierId: string | null): string {
  return `${unitId}|${qty}|${tierId ?? ""}`;
}

export function PosScreen({ data }: { data: PosData }) {
  const shift = data.shift;
  const router = useRouter();

  const [products, setProducts] = useState<PosProduct[]>(data.products);
  const [query, setQuery] = useState("");
  const [lines, setLines] = useState<CartLine[]>([]);
  const [customerId, setCustomerId] = useState("");
  const [tierId, setTierId] = useState<string | null>(data.defaultTierId);
  const [payment, setPayment] = useState("");
  const [state, setState] = useState<CreateSaleState>(initialState);
  const [cartError, setCartError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const searchRef = useRef<HTMLInputElement>(null);
  const paymentRef = useRef<HTMLInputElement>(null);
  const clientUuidRef = useRef<string | null>(null);
  const inFlightRef = useRef<Set<string>>(new Set());

  const customer: PosCustomer | undefined = data.customers.find(
    (row) => row.id === customerId
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return products;
    return products.filter((product) =>
      [product.name, product.sku ?? "", product.barcode ?? ""].some((value) =>
        value.toLowerCase().includes(q)
      )
    );
  }, [products, query]);

  const total = lines.reduce((sum, line) => sum + lineTotal(line), 0);
  const received = Math.max(0, Math.floor(Number(payment) || 0));
  const change = received - total;
  const canPay = lines.length > 0 && total > 0 && change >= 0 && !pending;

  // Harga selalu dari server (tier + harga grosir). Jalankan saat qty/satuan/tier berubah.
  useEffect(() => {
    const stale = lines.filter(
      (line) => line.resolvedFor !== priceKey(line.unitId, line.qty, tierId)
    );
    if (stale.length === 0) return;

    for (const line of stale) {
      const key = line.key;
      const requestedFor = priceKey(line.unitId, line.qty, tierId);
      const requestId = `${key}@${requestedFor}`;
      if (inFlightRef.current.has(requestId)) continue;
      inFlightRef.current.add(requestId);

      void resolveSalePriceAction({
        productId: line.productId,
        unitId: line.unitId,
        qty: line.qty,
        tierId,
      }).then((result) => {
        inFlightRef.current.delete(requestId);
        setLines((prev) =>
          prev.map((row) =>
            row.key === key
              ? {
                  ...row,
                  pricing: false,
                  unitPrice: result.price ?? row.unitPrice,
                  resolvedFor: requestedFor,
                }
              : row
          )
        );
        if (result.error) setCartError(result.error);
      });
    }
  }, [lines, tierId]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "F2") {
        event.preventDefault();
        searchRef.current?.focus();
      } else if (event.key === "F4") {
        event.preventDefault();
        paymentRef.current?.focus();
      } else if (event.key === "Escape") {
        setQuery("");
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const addProduct = useCallback(
    (product: PosProduct) => {
      setState(initialState);
      const unit =
        product.units.find((row) => row.factor === 1) ?? product.units[0];
      if (!unit) {
        setCartError(`Satuan produk ${product.name} belum diatur.`);
        return;
      }

      setLines((prev) => {
        const existing = prev.find(
          (line) =>
            line.productId === product.id && line.unitId === unit.unitId
        );
        if (existing) {
          return prev.map((line) =>
            line.key === existing.key
              ? { ...line, qty: Number((line.qty + 1).toFixed(3)), pricing: true }
              : line
          );
        }
        return [
          ...prev,
          {
            key: crypto.randomUUID(),
            productId: product.id,
            name: product.name,
            unitId: unit.unitId,
            unitName: unit.name,
            factor: unit.factor,
            qty: 1,
            unitPrice: unit.price,
            discount: 0,
            stockQty: product.stockQty,
            trackStock: product.trackStock,
            pricing: false,
            resolvedFor: priceKey(unit.unitId, 1, tierId),
          },
        ];
      });
    },
    [tierId]
  );

  function updateLine(key: string, patch: Partial<CartLine>) {
    setLines((prev) =>
      prev.map((line) => (line.key === key ? { ...line, ...patch } : line))
    );
  }

  function changeQty(line: CartLine, delta: number) {
    const next = Number((line.qty + delta).toFixed(3));
    if (next <= 0) return;
    updateLine(line.key, { qty: next, pricing: true });
  }

  function changeUnit(line: CartLine, unitId: string) {
    const product = products.find((row) => row.id === line.productId);
    const unit = product?.units.find((row) => row.unitId === unitId);
    if (!unit) return;
    updateLine(line.key, {
      unitId: unit.unitId,
      unitName: unit.name,
      factor: unit.factor,
      pricing: true,
    });
  }

  function onCustomerChange(value: string) {
    setCustomerId(value);
    const nextCustomer = data.customers.find((row) => row.id === value);
    const nextTier = nextCustomer?.tierId ?? data.defaultTierId;
    setTierId(nextTier);
    setLines((prev) =>
      prev.map((line) => ({ ...line, resolvedFor: "", pricing: true }))
    );

    void getPosCatalogAction(nextTier).then((result) => {
      if (result.products.length > 0 || result.error === null) {
        setProducts(result.products);
      }
    });
  }

  const stockWarning = lines.some(
    (line) =>
      line.trackStock && line.qty * line.factor > line.stockQty + 1e-9
  );

  function onSearchKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key !== "Enter") return;
    const q = query.trim().toLowerCase();
    if (!q) return;
    const match = products.find(
      (product) =>
        (product.barcode ?? "").toLowerCase() === q ||
        (product.sku ?? "").toLowerCase() === q
    );
    if (match) {
      event.preventDefault();
      addProduct(match);
      setQuery("");
    }
  }

  function submit() {
    if (!shift) return;
    setCartError(null);
    setState(initialState);

    if (lines.length === 0) {
      setCartError("Keranjang masih kosong.");
      return;
    }
    if (stockWarning) {
      setCartError("Ada qty yang melebihi stok. Periksa keranjang.");
      return;
    }
    if (change < 0) {
      setCartError("Uang diterima kurang dari total.");
      return;
    }
    if (lines.some((line) => line.pricing)) {
      setCartError("Harga masih dihitung. Coba lagi sebentar.");
      return;
    }

    if (!clientUuidRef.current) clientUuidRef.current = crypto.randomUUID();

    const payload = {
      clientUuid: clientUuidRef.current,
      tenantId: data.tenantId,
      outletId: shift.outletId,
      shiftId: shift.id,
      customerId: customerId || undefined,
      items: lines.map((line) => ({
        productId: line.productId,
        unitId: line.unitId,
        qty: line.qty,
        unitPrice: line.unitPrice,
        discount: line.discount,
      })),
      payments: [{ method: "tunai" as const, amount: received }],
    };

    const formData = new FormData();
    formData.set("payload", JSON.stringify(payload));

    startTransition(async () => {
      const result = await createSaleAction(initialState, formData);
      setState(result);
      if (result.success) {
        clientUuidRef.current = null;
        setLines([]);
        setPayment("");
        setCustomerId("");
        setTierId(data.defaultTierId);
        router.refresh();
        void getPosCatalogAction(data.defaultTierId).then((res) => {
          if (res.error === null) setProducts(res.products);
        });
      }
    });
  }

  return (
    <div className="mx-auto flex max-w-7xl flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Kasir</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            {data.tenantName} &middot; {shift?.outletName} &middot; shift dibuka{" "}
            {shift
              ? new Intl.DateTimeFormat("id-ID", {
                  timeStyle: "short",
                }).format(new Date(shift.openedAt))
              : ""}
          </p>
        </div>
        <div className="flex flex-wrap gap-3 text-sm">
          <Link
            href="/kasir/shift"
            className="inline-flex h-11 items-center rounded-md border border-input px-4 hover:bg-accent"
          >
            Tutup kasir / shift
          </Link>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_400px]">
        <section className="flex min-w-0 flex-col gap-3">
          <label className="flex flex-col gap-1 text-sm">
            <span className="sr-only">Cari produk</span>
            <input
              ref={searchRef}
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              onKeyDown={onSearchKeyDown}
              placeholder="Cari nama, SKU, atau scan barcode (F2)"
              className="h-12 rounded-md border border-input bg-background px-4 text-base"
              autoFocus
            />
          </label>

          {products.length === 0 ? (
            <p className="text-muted-foreground text-sm">
              Belum ada produk aktif. Tambah produk dulu di menu Produk.
            </p>
          ) : filtered.length === 0 ? (
            <p className="text-muted-foreground text-sm">
              Produk tidak ditemukan untuk &ldquo;{query}&rdquo;.
            </p>
          ) : (
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {filtered.map((product) => (
                <button
                  key={product.id}
                  type="button"
                  onClick={() => addProduct(product)}
                  className="flex min-h-24 flex-col justify-between gap-2 rounded-lg border bg-card p-3 text-left hover:bg-accent"
                >
                  <span className="text-sm font-medium">{product.name}</span>
                  <span className="flex flex-wrap items-baseline justify-between gap-1">
                    <span className="text-sm font-semibold">
                      {formatRupiah(product.price)}
                      <span className="text-muted-foreground text-xs font-normal">
                        /{product.baseUnitName}
                      </span>
                    </span>
                    {product.trackStock ? (
                      <span
                        className={`text-xs ${
                          product.isLow
                            ? "font-bold text-destructive"
                            : "text-muted-foreground"
                        }`}
                      >
                        Stok {formatQty(product.stockQty)}
                      </span>
                    ) : (
                      <span className="text-muted-foreground text-xs">Jasa</span>
                    )}
                  </span>
                </button>
              ))}
            </div>
          )}
        </section>

        <aside className="flex flex-col gap-3 lg:sticky lg:top-4 lg:self-start">
          <div className="rounded-lg border bg-card">
            <div className="border-b px-4 py-3">
              <h2 className="font-semibold">Keranjang</h2>
            </div>

            {lines.length === 0 ? (
              <p className="text-muted-foreground p-4 text-sm">
                Belum ada item. Klik produk di kiri atau scan barcode.
              </p>
            ) : (
              <ul className="divide-y">
                {lines.map((line) => {
                  const product = products.find(
                    (row) => row.id === line.productId
                  );
                  const overStock =
                    line.trackStock &&
                    line.qty * line.factor > line.stockQty + 1e-9;

                  return (
                    <li key={line.key} className="flex flex-col gap-2 p-3">
                      <div className="flex items-start justify-between gap-2">
                        <span className="text-sm font-medium">{line.name}</span>
                        <button
                          type="button"
                          onClick={() =>
                            setLines((prev) =>
                              prev.filter((row) => row.key !== line.key)
                            )
                          }
                          className="text-muted-foreground h-11 px-2 text-xs hover:text-destructive"
                          aria-label={`Hapus ${line.name}`}
                        >
                          Hapus
                        </button>
                      </div>

                      <div className="flex flex-wrap items-center gap-2">
                        <div className="flex items-center">
                          <Button
                            type="button"
                            variant="outline"
                            className="h-11 w-11"
                            onClick={() => changeQty(line, -1)}
                            aria-label={`Kurangi ${line.name}`}
                          >
                            &minus;
                          </Button>
                          <input
                            type="number"
                            min={0.001}
                            step={0.001}
                            value={line.qty}
                            onChange={(event) => {
                              const next = Number(event.target.value);
                              if (Number.isFinite(next) && next > 0) {
                                updateLine(line.key, { qty: next, pricing: true });
                              }
                            }}
                            aria-label={`Qty ${line.name}`}
                            className="h-11 w-16 border-y border-input bg-background px-2 text-center"
                          />
                          <Button
                            type="button"
                            variant="outline"
                            className="h-11 w-11"
                            onClick={() => changeQty(line, 1)}
                            aria-label={`Tambah ${line.name}`}
                          >
                            +
                          </Button>
                        </div>

                        <select
                          value={line.unitId}
                          onChange={(event) =>
                            changeUnit(line, event.target.value)
                          }
                          aria-label={`Satuan ${line.name}`}
                          className="h-11 rounded-md border border-input bg-background px-2 text-sm"
                        >
                          {(product?.units ?? []).map((unit) => (
                            <option key={unit.unitId} value={unit.unitId}>
                              {unit.name}
                            </option>
                          ))}
                        </select>

                        <button
                          type="button"
                          onClick={() => {
                            if (!product) return;
                            if (line.unitId === product.baseUnitId) return;
                            const base = product.units.find(
                              (unit) => unit.unitId === product.baseUnitId
                            );
                            if (base) changeUnit(line, base.unitId);
                          }}
                          className="text-muted-foreground h-11 px-2 text-xs underline-offset-2 hover:underline"
                        >
                          ke {product?.baseUnitName ?? "satuan dasar"}
                        </button>
                      </div>

                      <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
                        <span>
                          {line.pricing
                            ? "Menghitung harga..."
                            : `${formatRupiah(line.unitPrice)} × ${formatQty(
                                line.qty
                              )} ${line.unitName}`}
                        </span>
                        <label className="flex items-center gap-1">
                          <span className="text-muted-foreground text-xs">
                            Diskon
                          </span>
                          <input
                            type="number"
                            min={0}
                            step={1}
                            value={line.discount}
                            onChange={(event) =>
                              updateLine(line.key, {
                                discount: Math.max(
                                  0,
                                  Math.floor(Number(event.target.value) || 0)
                                ),
                              })
                            }
                            aria-label={`Diskon ${line.name}`}
                            className="h-11 w-24 rounded-md border border-input bg-background px-2 text-right"
                          />
                        </label>
                      </div>

                      <div className="flex items-center justify-between text-sm">
                        <span
                          className={
                            overStock
                              ? "font-semibold text-destructive"
                              : "text-muted-foreground"
                          }
                        >
                          {overStock
                            ? `Melebihi stok (${formatQty(line.stockQty)} ${line.unitName})`
                            : ""}
                        </span>
                        <span className="font-semibold">
                          {formatRupiah(lineTotal(line))}
                        </span>
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}

            <div className="flex flex-col gap-3 border-t p-4 text-sm">
              <label className="flex flex-col gap-1">
                <span className="text-muted-foreground">
                  Pelanggan (opsional)
                </span>
                <select
                  value={customerId}
                  onChange={(event) => onCustomerChange(event.target.value)}
                  className="h-11 rounded-md border border-input bg-background px-2"
                >
                  <option value="">Tanpa pelanggan (Umum)</option>
                  {data.customers.map((row) => (
                    <option key={row.id} value={row.id}>
                      {row.name}
                    </option>
                  ))}
                </select>
              </label>

              <div className="flex items-baseline justify-between text-base">
                <span className="font-medium">Total</span>
                <span className="text-xl font-bold">{formatRupiah(total)}</span>
              </div>

              <label className="flex flex-col gap-1">
                <span className="text-muted-foreground">Uang diterima (Rp)</span>
                <input
                  ref={paymentRef}
                  type="number"
                  inputMode="numeric"
                  min={0}
                  step={1}
                  value={payment}
                  onChange={(event) => setPayment(event.target.value)}
                  placeholder={String(total)}
                  className="h-12 rounded-md border border-input bg-background px-3 text-lg font-semibold"
                />
              </label>

              <div className="flex flex-wrap gap-2">
                <Button
                  type="button"
                  variant="outline"
                  className="h-11"
                  onClick={() => setPayment(String(total))}
                >
                  Uang pas
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  className="h-11"
                  onClick={() => setPayment("50000")}
                >
                  50.000
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  className="h-11"
                  onClick={() => setPayment("100000")}
                >
                  100.000
                </Button>
              </div>

              <div className="flex items-baseline justify-between">
                <span className="text-muted-foreground">Kembalian</span>
                <span
                  className={`text-lg font-bold ${
                    change < 0 ? "text-destructive" : ""
                  }`}
                >
                  {formatRupiah(change)}
                </span>
              </div>

              {customer && customer.creditLimit > 0 ? (
                <p className="text-muted-foreground text-xs">
                  Limit kredit {customer.name}:{" "}
                  {formatRupiah(customer.creditLimit)}
                </p>
              ) : null}

              <Button
                type="button"
                onClick={submit}
                disabled={!canPay || stockWarning}
                className="h-12 text-base"
              >
                {pending ? "Menyimpan..." : "Bayar & simpan"}
              </Button>

              {cartError ? (
                <p className="text-sm text-destructive" role="alert">
                  {cartError}
                </p>
              ) : null}
              {state.error ? (
                <p className="text-sm text-destructive" role="alert">
                  {state.error}
                </p>
              ) : null}
            </div>
          </div>

          {state.success ? (
            <div className="rounded-lg border border-green-600/40 bg-green-50 p-4 text-sm">
              <p className="font-semibold text-green-800" role="status">
                Transaksi tersimpan: {state.success.invoiceNo}
              </p>
              <dl className="mt-2 grid gap-1">
                <div className="flex justify-between">
                  <dt>Total</dt>
                  <dd>{formatRupiah(state.success.total)}</dd>
                </div>
                <div className="flex justify-between">
                  <dt>Dibayar</dt>
                  <dd>{formatRupiah(state.success.paidAmount)}</dd>
                </div>
                <div className="flex justify-between font-semibold">
                  <dt>Kembalian</dt>
                  <dd>{formatRupiah(state.success.changeAmount)}</dd>
                </div>
              </dl>
            </div>
          ) : null}
        </aside>
      </div>
    </div>
  );
}
