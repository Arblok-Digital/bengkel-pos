"use client";

import { useActionState, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  createPurchaseOrderAction,
  type PurchaseOrderActionState,
} from "@/features/purchasing/actions";

type OutletOption = { id: string; name: string };
type SupplierOption = { id: string; name: string };
type ProductOption = { id: string; name: string; baseUnitId: string | null };
type UnitOption = { id: string; name: string };

const initialState: PurchaseOrderActionState = {
  error: null,
  success: null,
};

type Item = {
  productId: string;
  productName: string;
  unitId: string;
  unitName: string;
  qty: string;
  unitPrice: string;
  note: string;
};

export function CreatePurchaseOrderForm({
  tenantId,
  outlets,
  suppliers,
  products,
  units,
}: {
  tenantId: string;
  outlets: OutletOption[];
  suppliers: SupplierOption[];
  products: ProductOption[];
  units: UnitOption[];
}) {
  const [outletOptions] = useState<OutletOption[]>(outlets);
  const [supplierOptions] = useState<SupplierOption[]>(suppliers);
  const [productOptions] = useState<ProductOption[]>(products);
  const [unitOptions] = useState<UnitOption[]>(units);
  const [supplierId, setSupplierId] = useState("");
  const [outletId, setOutletId] = useState("");
  const [items, setItems] = useState<Item[]>([
    {
      productId: "",
      productName: "",
      unitId: "",
      unitName: "",
      qty: "1",
      unitPrice: "0",
      note: "",
    },
  ]);
  const [state, formAction, pending] = useActionState(
    createPurchaseOrderAction,
    initialState
  );

  const addItem = () => {
    setItems([
      ...items,
      {
        productId: "",
        productName: "",
        unitId: "",
        unitName: "",
        qty: "1",
        unitPrice: "0",
        note: "",
      },
    ]);
  };

  const removeItem = (index: number) => {
    setItems(items.filter((_, i) => i !== index));
  };

  return (
    <form action={formAction} className="rounded-lg border bg-card p-4 space-y-4">
      <input type="hidden" name="tenantId" value={tenantId} />
      <input type="hidden" name="clientUuid" defaultValue={crypto.randomUUID()} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Outlet</span>
          <select
            name="outletId"
            required
            value={outletId}
            onChange={(e: React.ChangeEvent<HTMLSelectElement>) =>
              setOutletId(e.target.value)
            }
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="">Pilih outlet</option>
            {outletOptions.map((o) => (
              <option key={o.id} value={o.id}>{o.name}</option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Supplier</span>
          <select
            name="supplierId"
            required
            value={supplierId}
            onChange={(e: React.ChangeEvent<HTMLSelectElement>) =>
              setSupplierId(e.target.value)
            }
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="">Pilih supplier</option>
            {supplierOptions.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">Catatan</span>
          <textarea
            name="note"
            rows={2}
            maxLength={500}
            className="h-24 rounded-md border border-input bg-background px-2"
          />
        </label>
      </div>

      <div className="bg-muted/50 rounded-lg p-3">
        <h3 className="text-sm font-medium mb-2">Item PO</h3>
        <div className="space-y-2">
          {items.map((item, index) => {
            const product = productOptions.find((p) => p.id === item.productId);
            return (
              <div key={index} className="grid gap-2 sm:grid-cols-5 items-end">
                <select
                  name={`items_${index}_productId`}
                  required
                  value={item.productId}
                  onChange={(e: React.ChangeEvent<HTMLSelectElement>) => {
                    const pid = e.target.value;
                    const p = productOptions.find((x) => x.id === pid);
                    setItems((prev) =>
                      prev.map((it, i) =>
                        i === index
                          ? {
                              ...it,
                              productId: pid,
                              productName: p?.name ?? "",
                              unitId: p?.baseUnitId ?? "",
                              unitName: "",
                            }
                          : it
                      )
                    );
                  }}
                  className="h-9 rounded-md border border-input bg-background px-2 text-sm"
                >
                  <option value="">Pilih produk</option>
                  {productOptions.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
                <input
                  disabled
                  defaultValue={product?.name ?? ""}
                  className="text-sm"
                  placeholder="Produk"
                />
                <select
                  name={`items_${index}_unitId`}
                  required
                  value={item.unitId}
                  onChange={(e: React.ChangeEvent<HTMLSelectElement>) =>
                    setItems((prev) =>
                      prev.map((it, i) =>
                        i === index
                          ? {
                              ...it,
                              unitId: e.target.value,
                              unitName: unitOptions.find(
                                (u) => u.id === e.target.value
                              )?.name ?? "",
                            }
                          : it
                      )
                    )}
                  className="h-9 rounded-md border border-input bg-background px-2 text-sm"
                >
                  <option value="">Satuan</option>
                  {unitOptions.map((u) => (
                    <option key={u.id} value={u.id}>{u.name}</option>
                  ))}
                </select>
                <input
                  name={`items_${index}_qty`}
                  type="number"
                  min="0.0001"
                  step="0.0001"
                  defaultValue={item.qty}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                    setItems((prev) =>
                      prev.map((it, i) =>
                        i === index ? { ...it, qty: e.target.value } : it
                      )
                    )}
                  className="h-9 rounded-md border border-input bg-background px-2 text-sm"
                />
                <input
                  name={`items_${index}_unitPrice`}
                  type="number"
                  min="0"
                  step="1"
                  defaultValue={item.unitPrice}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                    setItems((prev) =>
                      prev.map((it, i) =>
                        i === index
                          ? { ...it, unitPrice: e.target.value }
                          : it
                      )
                    )}
                  className="h-9 rounded-md border border-input bg-background px-2 text-sm"
                />
                <Button
                  type="button"
                  onClick={() => removeItem(index)}
                  variant="destructive"
                  size="sm"
                  disabled={items.length === 1}
                >
                  Hapus
                </Button>
              </div>
            );
          })}
          <Button type="button" onClick={addItem} size="sm" className="h-9">
            + Tambah item
          </Button>
        </div>
      </div>

      <input type="hidden" name="items" value={JSON.stringify(items)} />

      <div className="mt-4 flex items-center gap-3">
        <Button
          type="submit"
          disabled={pending || !supplierId || !outletId}
          className="h-9"
        >
          {pending ? "Membuat PO..." : "Buat PO (draft)"}
        </Button>
        {state.error ? (
          <p className="text-sm text-destructive" role="alert">
            {state.error}
          </p>
        ) : null}
        {state.success ? (
          <p className="text-sm text-success" role="status">
            PO {state.success.poNo} dibuat (total {state.success.total}).
          </p>
        ) : null}
      </div>
    </form>
  );
}
