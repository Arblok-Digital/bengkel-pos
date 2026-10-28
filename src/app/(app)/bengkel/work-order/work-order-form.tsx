"use client";

import { useActionState, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  createWorkOrderAction,
  type WorkOrderActionState,
} from "@/features/workorder/actions";
import type { CustomerOption } from "@/features/workorder/queries";

const initialState: WorkOrderActionState = { error: null };

export function WorkOrderForm({
  tenantId,
  outletId,
  customers,
}: {
  tenantId: string;
  outletId: string;
  customers: CustomerOption[];
}) {
  const [state, formAction, pending] = useActionState(
    createWorkOrderAction,
    initialState
  );
  const [items, setItems] = useState<{ productId: string; unitId: string; qty: string; unitPrice: string; note: string }[]>([
    { productId: "", unitId: "", qty: "", unitPrice: "", note: "" },
  ]);

  const addItem = () => {
    setItems([...items, { productId: "", unitId: "", qty: "", unitPrice: "", note: "" }]);
  };
  const removeItem = (idx: number) => {
    if (items.length > 1) setItems(items.filter((_, i) => i !== idx));
  };

  return (
    <form action={formAction} id="tambah-wo" className="rounded-lg border bg-card p-4 space-y-4">
      <input type="hidden" name="tenantId" value={tenantId} />
      <input type="hidden" name="outletId" value={outletId} />

      <h2 className="text-lg font-semibold">Work Order Baru</h2>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Pelanggan</span>
          <select
            name="customerId"
            required
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="">Pilih pelanggan</option>
            {customers.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">Keluhan</span>
          <textarea
            name="complaint"
            rows={2}
            placeholder="Contoh: Mobil berisik saat rem, AC tidak dingin"
            className="h-9 rounded-md border border-input bg-background px-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">Diagnosis (opsional)</span>
          <textarea
            name="diagnosis"
            rows={2}
            placeholder="Contoh: Kaki rem bocor, pendingin AC rusak"
            className="h-9 rounded-md border border-input bg-background px-2"
          />
        </label>
      </div>

      <div className="mt-4 rounded-lg border bg-muted/40 p-4">
        <h3 className="text-sm font-semibold mb-3">Item (Jasa / Sparepart)</h3>
        <div className="space-y-3">
          {items.map((item, idx) => (
            <div key={idx} className="grid gap-3 sm:grid-cols-6 items-end">
              <div className="flex flex-col gap-1 text-sm">
                <span className="font-medium">Produk</span>
                <select
                  name={`items[${idx}].productId`}
                  className="h-9 rounded-md border border-input bg-background px-2 text-xs"
                >
                  <option value="">Pilih produk</option>
                </select>
              </div>
              <div className="flex flex-col gap-1 text-sm">
                <span className="font-medium">Satuan</span>
                <select
                  name={`items[${idx}].unitId`}
                  className="h-9 rounded-md border border-input bg-background px-2 text-xs"
                >
                  <option value="">Pilih satuan</option>
                </select>
              </div>
              <div className="flex flex-col gap-1 text-sm">
                <span className="font-medium">Qty</span>
                <input
                  name={`items[${idx}].qty`}
                  type="number"
                  step="0.01"
                  min="0"
                  className="h-9 rounded-md border border-input bg-background px-2 text-xs"
                />
              </div>
              <div className="flex flex-col gap-1 text-sm">
                <span className="font-medium">Harga Satuan</span>
                <input
                  name={`items[${idx}].unitPrice`}
                  type="number"
                  min="0"
                  className="h-9 rounded-md border border-input bg-background px-2 text-xs"
                />
              </div>
              <div className="flex flex-col gap-1 text-sm sm:col-span-2">
                <span className="font-medium">Catatan</span>
                <input
                  name={`items[${idx}].note`}
                  placeholder="Opsional"
                  className="h-9 rounded-md border border-input bg-background px-2 text-xs"
                />
              </div>
              <div className="flex items-end">
                <Button
                  type="button"
                  variant="destructive"
                  size="sm"
                  onClick={() => removeItem(idx)}
                  disabled={items.length === 1}
                >
                  Hapus
                </Button>
              </div>
            </div>
          ))}
          <div className="flex justify-end">
            <Button type="button" size="sm" onClick={addItem}>
              + Tambah Item
            </Button>
          </div>
        </div>
      </div>

      <div className="mt-4 flex items-center gap-3">
        <Button type="submit" disabled={pending} className="h-9">
          {pending ? "Menyimpan..." : "Simpan Work Order"}
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
