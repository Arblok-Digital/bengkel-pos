"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  adjustStockAction,
  type StockAdjustmentState,
} from "@/features/inventory/actions";

const initialState: StockAdjustmentState = { error: null };

export function AdjustStockForm({
  tenantId,
  products,
  outlets,
  clientUuid,
}: {
  tenantId: string;
  products: { id: string; name: string }[];
  outlets: { id: string; name: string }[];
  clientUuid: string;
}) {
  const [state, formAction, pending] = useActionState(
    adjustStockAction,
    initialState
  );

  return (
    <form action={formAction} className="rounded-lg border bg-card p-4">
      <input type="hidden" name="tenantId" value={tenantId} />
      <input type="hidden" name="clientUuid" value={clientUuid} />

      <div className="grid gap-3">
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Produk</span>
          <select
            name="productId"
            required
            defaultValue=""
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="" disabled>
              Pilih produk
            </option>
            {products.map((product) => (
              <option key={product.id} value={product.id}>
                {product.name}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Outlet</span>
          <select
            name="outletId"
            required
            defaultValue=""
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="" disabled>
              Pilih outlet
            </option>
            {outlets.map((outlet) => (
              <option key={outlet.id} value={outlet.id}>
                {outlet.name}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Qty penyesuaian</span>
          <input
            name="qtyBase"
            type="number"
            step={0.001}
            required
            placeholder="cth: 5 atau -3"
            className="h-9 rounded-md border border-input bg-background px-2"
          />
          <span className="text-muted-foreground text-xs">
            Positif = tambah, negatif = kurangi.
          </span>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Alasan</span>
          <textarea
            name="reason"
            required
            minLength={3}
            maxLength={500}
            rows={3}
            placeholder="cth: stok opname, barang rusak, koreksi input"
            className="rounded-md border border-input bg-background p-2"
          />
        </label>
      </div>

      <div className="mt-4 flex items-center gap-3">
        <Button type="submit" disabled={pending} className="h-9">
          {pending ? "Menyimpan..." : "Simpan penyesuaian"}
        </Button>
        {state.error ? (
          <p className="text-sm text-destructive" role="alert">
            {state.error}
          </p>
        ) : null}
      </div>
    </form>
  );
}
