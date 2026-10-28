"use client";

import { useActionState, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  createWorkOrderAction,
  type WorkOrderActionState,
} from "@/features/workorder/actions";
import type {
  CustomerOption,
  MechanicOption,
  ProductFormOption,
  VehicleFormOption,
} from "@/features/workorder/queries";
import { formatRupiah, mulQty } from "@/lib/money";

const initialState: WorkOrderActionState = { error: null };

type ItemDraft = {
  key: string;
  productId: string;
  unitId: string;
  qty: string;
  unitPrice: string;
  note: string;
};

function emptyItem(): ItemDraft {
  return {
    key: crypto.randomUUID(),
    productId: "",
    unitId: "",
    qty: "1",
    unitPrice: "",
    note: "",
  };
}

export function WorkOrderForm({
  tenantId,
  outletId,
  customers,
  vehicles,
  products,
  mechanics,
}: {
  tenantId: string;
  outletId: string;
  customers: CustomerOption[];
  vehicles: VehicleFormOption[];
  products: ProductFormOption[];
  mechanics: MechanicOption[];
}) {
  const [state, formAction, pending] = useActionState(
    createWorkOrderAction,
    initialState
  );
  const [customerId, setCustomerId] = useState("");
  const [vehicleId, setVehicleId] = useState("");
  const [items, setItems] = useState<ItemDraft[]>([emptyItem()]);

  const customerVehicles = vehicles.filter(
    (vehicle) => vehicle.customerId === customerId
  );

  function updateItem(key: string, patch: Partial<ItemDraft>) {
    setItems((prev) =>
      prev.map((item) => (item.key === key ? { ...item, ...patch } : item))
    );
  }

  function changeProduct(item: ItemDraft, productId: string) {
    const product = products.find((row) => row.id === productId);
    const unit = product?.units[0];
    updateItem(item.key, {
      productId,
      unitId: unit?.id ?? "",
      unitPrice: unit ? String(unit.price) : "",
    });
  }

  function changeUnit(item: ItemDraft, unitId: string) {
    const product = products.find((row) => row.id === item.productId);
    const unit = product?.units.find((row) => row.id === unitId);
    updateItem(item.key, {
      unitId,
      unitPrice: unit ? String(unit.price) : item.unitPrice,
    });
  }

  const payloadItems = items
    .filter((item) => item.productId !== "" && item.unitId !== "")
    .map((item) => ({
      productId: item.productId,
      unitId: item.unitId,
      qty: Number(item.qty),
      unitPrice: Number(item.unitPrice),
      note: item.note.trim() === "" ? null : item.note.trim(),
    }));

  return (
    <form
      action={formAction}
      id="tambah-wo"
      className="space-y-4 rounded-lg border bg-card p-4"
    >
      <input type="hidden" name="tenantId" value={tenantId} />
      <input type="hidden" name="outletId" value={outletId} />
      <input type="hidden" name="items" value={JSON.stringify(payloadItems)} />

      <h2 className="text-lg font-semibold">Work Order Baru</h2>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Pelanggan</span>
          <select
            name="customerId"
            aria-label="Pelanggan"
            required
            value={customerId}
            onChange={(event) => {
              setCustomerId(event.target.value);
              setVehicleId("");
            }}
            className="min-h-11 rounded-md border border-input bg-background px-2"
          >
            <option value="">Pilih pelanggan</option>
            {customers.map((customer) => (
              <option key={customer.id} value={customer.id}>
                {customer.name}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Kendaraan</span>
          <select
            name="vehicleId"
            aria-label="Kendaraan"
            required
            value={vehicleId}
            onChange={(event) => setVehicleId(event.target.value)}
            disabled={customerId === "" || customerVehicles.length === 0}
            className="min-h-11 rounded-md border border-input bg-background px-2"
          >
            <option value="">
              {customerId === ""
                ? "Pilih pelanggan dulu"
                : customerVehicles.length === 0
                ? "Pelanggan belum punya kendaraan"
                : "Pilih kendaraan"}
            </option>
            {customerVehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {vehicle.label}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Mekanik (opsional)</span>
          <select
            name="mechanicId"
            className="min-h-11 rounded-md border border-input bg-background px-2"
          >
            <option value="">Belum ditugaskan</option>
            {mechanics.map((mechanic) => (
              <option key={mechanic.id} value={mechanic.id}>
                {mechanic.name}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Odometer (km)</span>
          <input
            name="odometer"
            type="number"
            min={0}
            step={1}
            placeholder="Opsional"
            className="min-h-11 rounded-md border border-input bg-background px-2"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">Keluhan</span>
          <textarea
            name="complaint"
            required
            rows={2}
            placeholder="Contoh: Mobil berisik saat rem, AC tidak dingin"
            className="min-h-11 rounded-md border border-input bg-background px-2 py-2"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">Diagnosis (opsional)</span>
          <textarea
            name="diagnosis"
            rows={2}
            placeholder="Contoh: Kaki rem bocor, pendingin AC rusak"
            className="min-h-11 rounded-md border border-input bg-background px-2 py-2"
          />
        </label>
      </div>

      <div className="rounded-lg border bg-muted/40 p-4">
        <h3 className="mb-3 text-sm font-semibold">Item (Jasa / Sparepart)</h3>
        <div className="space-y-3">
          {items.map((item, idx) => {
            const product = products.find((row) => row.id === item.productId);
            const price = Number(item.unitPrice);
            const subtotal =
              Number.isInteger(price) && price >= 0 && Number(item.qty) > 0
                ? mulQty(item.qty, price)
                : 0;

            return (
              <div
                key={item.key}
                className="grid items-end gap-3 sm:grid-cols-2 lg:grid-cols-12"
              >
                <label className="flex flex-col gap-1 text-sm lg:col-span-3">
                  <span className="font-medium">Produk item {idx + 1}</span>
                  <select
                    aria-label={`Produk item ${idx + 1}`}
                    required
                    value={item.productId}
                    onChange={(event) =>
                      changeProduct(item, event.target.value)
                    }
                    className="min-h-11 rounded-md border border-input bg-background px-2 text-sm"
                  >
                    <option value="">Pilih produk</option>
                    {products.map((row) => (
                      <option key={row.id} value={row.id}>
                        {row.name}
                        {row.kind === "jasa" ? " (jasa)" : ""}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="flex flex-col gap-1 text-sm lg:col-span-2">
                  <span className="font-medium">Satuan item {idx + 1}</span>
                  <select
                    aria-label={`Satuan item ${idx + 1}`}
                    required
                    disabled={!product}
                    value={item.unitId}
                    onChange={(event) => changeUnit(item, event.target.value)}
                    className="min-h-11 rounded-md border border-input bg-background px-2 text-sm"
                  >
                    <option value="">Pilih satuan</option>
                    {(product?.units ?? []).map((unit) => (
                      <option key={unit.id} value={unit.id}>
                        {unit.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="flex flex-col gap-1 text-sm lg:col-span-1">
                  <span className="font-medium">Qty item {idx + 1}</span>
                  <input
                    aria-label={`Qty item ${idx + 1}`}
                    type="number"
                    step="0.001"
                    min="0.001"
                    required
                    value={item.qty}
                    onChange={(event) =>
                      updateItem(item.key, { qty: event.target.value })
                    }
                    className="min-h-11 rounded-md border border-input bg-background px-2 text-right text-sm"
                  />
                </label>

                <label className="flex flex-col gap-1 text-sm lg:col-span-2">
                  <span className="font-medium">Harga satuan item {idx + 1}</span>
                  <input
                    aria-label={`Harga satuan item ${idx + 1}`}
                    type="number"
                    min="0"
                    step="1"
                    required
                    value={item.unitPrice}
                    onChange={(event) =>
                      updateItem(item.key, { unitPrice: event.target.value })
                    }
                    className="min-h-11 rounded-md border border-input bg-background px-2 text-right text-sm"
                  />
                </label>

                <label className="flex flex-col gap-1 text-sm lg:col-span-2">
                  <span className="font-medium">Catatan item {idx + 1}</span>
                  <input
                    aria-label={`Catatan item ${idx + 1}`}
                    placeholder="Opsional"
                    value={item.note}
                    onChange={(event) =>
                      updateItem(item.key, { note: event.target.value })
                    }
                    className="min-h-11 rounded-md border border-input bg-background px-2 text-sm"
                  />
                </label>

                <div className="flex items-center justify-between gap-2 lg:col-span-2">
                  <span className="font-mono text-sm font-medium">
                    {formatRupiah(subtotal)}
                  </span>
                  <Button
                    type="button"
                    variant="destructive"
                    size="sm"
                    className="min-h-11"
                    onClick={() =>
                      setItems((prev) =>
                        prev.length === 1
                          ? [emptyItem()]
                          : prev.filter((row) => row.key !== item.key)
                      )
                    }
                  >
                    Hapus
                  </Button>
                </div>
              </div>
            );
          })}

          <div className="flex justify-end">
            <Button
              type="button"
              size="sm"
              className="min-h-11"
              onClick={() => setItems((prev) => [...prev, emptyItem()])}
            >
              + Tambah Item
            </Button>
          </div>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={pending} className="min-h-11 px-4">
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
