"use client";

import { useActionState, useEffect, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  receiveGoodsAction,
  type ReceiveGoodsActionState,
} from "@/features/purchasing/actions";
import {
  getOutletOptions,
  getPoItemsForReceiving,
  getProductOptions,
  getSupplierOptions,
  getUnitOptions,
} from "@/features/purchasing/queries";

const initialState: ReceiveGoodsActionState = {
  error: null,
  success: null,
};

type GrItem = {
  productId: string;
  productName: string;
  unitId: string;
  unitName: string;
  qty: string;
  unitCost: string;
  purchaseOrderItemId: string;
  note: string;
};

export function ReceiveGoodsForm() {
  const [outlets, setOutlets] = useState<{ id: string; name: string }[]>([]);
  const [suppliers, setSuppliers] = useState<{ id: string; name: string }[]>(
    []
  );
  const [products, setProducts] = useState<{
    id: string;
    name: string;
    baseUnitId: string | null;
  }[]>([]);
  const [units, setUnits] = useState<{ id: string; name: string }[]>([]);
  const [poItems, setPoItems] = useState<{
    id: string;
    productId: string;
    productName: string;
    unitId: string;
    unitName: string;
    remainingQtyBase: number;
    unitCost: number;
  }[]>([]);
  const [items, setItems] = useState<GrItem[]>([
    {
      productId: "",
      productName: "",
      unitId: "",
      unitName: "",
      qty: "1",
      unitCost: "0",
      purchaseOrderItemId: "",
      note: "",
    },
  ]);
  const [supplierId, setSupplierId] = useState("");
  const [outletId, setOutletId] = useState("");
  const [purchaseOrderId, setPurchaseOrderId] = useState("");

  useEffect(() => {
    getOutletOptions().then(setOutlets);
    getSupplierOptions().then(setSuppliers);
    getProductOptions().then(setProducts);
    getUnitOptions().then(setUnits);
  }, []);

  const [state, formAction, pending] = useActionState(
    receiveGoodsAction,
    initialState
  );

  const handlePoChange = async (id: string) => {
    setPurchaseOrderId(id);
    if (!id) {
      setPoItems([]);
      return;
    }
    const rows = await getPoItemsForReceiving(id);
    setPoItems(
      rows.filter((r) => r.remainingQtyBase > 0).map((r) => ({
        id: r.id,
        productId: r.productId,
        productName: r.productName,
        unitId: r.unitId,
        unitName: r.unitName,
        remainingQtyBase: r.remainingQtyBase,
        unitCost: r.unitCost,
      }))
    );
  };

  const addItem = () => {
    setItems([
      ...items,
      {
        productId: "",
        productName: "",
        unitId: "",
        unitName: "",
        qty: "1",
        unitCost: "0",
        purchaseOrderItemId: "",
        note: "",
      },
    ]);
  };

  const removeItem = (index: number) => {
    setItems(items.filter((_, i) => i !== index));
  };

  const selectPoItem = (index: number, poItemId: string) => {
    const poItem = poItems.find((p) => p.id === poItemId);
    if (!poItem) return;
    setItems((prev) =>
      prev.map((it, i) =>
        i === index
          ? {
              ...it,
              productId: poItem.productId,
              productName: poItem.productName,
              unitId: poItem.unitId,
              unitName: poItem.unitName,
              unitCost: String(poItem.unitCost),
              purchaseOrderItemId: poItem.id,
            }
          : it
      )
    );
  };

  return (
    <form action={formAction} className="rounded-lg border bg-card p-4 space-y-4">
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
            {outlets.map((o) => (
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
            {suppliers.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">PO Referensi (opsional)</span>
          <select
            name="purchaseOrderId"
            value={purchaseOrderId}
            onChange={(e: React.ChangeEvent<HTMLSelectElement>) =>
              handlePoChange(e.target.value)
            }
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="">Pilih PO untuk diterima</option>
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

      {poItems.length > 0 && (
        <div className="bg-blue-50 rounded-lg p-3 border border-blue-100">
          <h3 className="text-sm font-medium mb-2">Item PO yang tersisa</h3>
          <div className="space-y-1">
            {poItems.map((p) => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => {
                    const emptyIdx = items.findIndex(
                      (it) => it.productId === ""
                    );
                    if (emptyIdx !== -1) {
                      selectPoItem(emptyIdx, p.id);
                    } else {
                      addItem();
                      selectPoItem(items.length, p.id);
                    }
                  }}
                className="w-full text-left text-sm px-3 py-2 rounded border border-input hover:bg-blue-100 transition"
              >
                {p.productName} · {p.unitName} · tersisa{" "}
                {p.remainingQtyBase.toLocaleString("id-ID")} @ Rp{" "}
                {p.unitCost.toLocaleString("id-ID")}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="bg-muted/50 rounded-lg p-3">
        <h3 className="text-sm font-medium mb-2">Item Penerimaan</h3>
        <div className="space-y-2">
          {items.map((item, index) => {
            const product = products.find((p) => p.id === item.productId);
            return (
              <div key={index} className="grid gap-2 sm:grid-cols-6 items-end">
                <select
                  name={`items_${index}_productId`}
                  required
                  value={item.productId}
                  onChange={(e: React.ChangeEvent<HTMLSelectElement>) => {
                    const pid = e.target.value;
                    const p = products.find((x) => x.id === pid);
                    setItems((prev) =>
                      prev.map((it, i) =>
                        i === index
                          ? {
                              ...it,
                              productId: pid,
                              productName: p?.name ?? "",
                              unitId: p?.baseUnitId ?? "",
                              unitName: units.find(
                                (u) => u.id === (p?.baseUnitId ?? "")
                              )?.name ?? "",
                              purchaseOrderItemId: "",
                              unitCost: "0",
                            }
                          : it
                      )
                    );
                  }}
                  className="h-9 rounded-md border border-input bg-background px-2 text-sm"
                >
                  <option value="">Pilih produk</option>
                  {products.map((p) => (
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
                              unitName: units.find(
                                (u) => u.id === e.target.value
                              )?.name ?? "",
                            }
                          : it
                      )
                    )}
                  className="h-9 rounded-md border border-input bg-background px-2 text-sm"
                >
                  <option value="">Satuan</option>
                  {units.map((u) => (
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
                  name={`items_${index}_unitCost`}
                  type="number"
                  min="0"
                  step="1"
                  defaultValue={item.unitCost}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                    setItems((prev) =>
                      prev.map((it, i) =>
                        i === index
                          ? { ...it, unitCost: e.target.value }
                          : it
                      )
                    )}
                  className="h-9 rounded-md border border-input bg-background px-2 text-sm"
                />
                <input
                  name={`items_${index}_purchaseOrderItemId`}
                  type="hidden"
                  defaultValue={item.purchaseOrderItemId}
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
          {pending ? "Menerima barang..." : "Terima barang (posting stok)"}
        </Button>
        {state.error ? (
          <p className="text-sm text-destructive" role="alert">
            {state.error}
          </p>
        ) : null}
        {state.success ? (
          <p className="text-sm text-success" role="status">
            GR {state.success.grNo} diposting (total {state.success.total}).
          </p>
        ) : null}
      </div>
    </form>
  );
}
