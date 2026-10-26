"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  createProductAction,
  deleteProductAction,
  updateProductAction,
  type ProductActionState,
} from "@/features/catalog/product-actions";
import type { CatalogItem, ProductRow } from "@/features/catalog/queries";

type BaseProps = {
  tenantId: string;
  categories: CatalogItem[];
  units: CatalogItem[];
};

const initialState: ProductActionState = { error: null };

export function ProductCreateForm({ tenantId, categories, units }: BaseProps) {
  const [state, formAction, pending] = useActionState(
    createProductAction,
    initialState
  );

  return (
    <form
      action={formAction}
      className="mt-4 rounded-lg border bg-card p-4"
    >
      <input type="hidden" name="tenantId" value={tenantId} />
      <ProductFields categories={categories} units={units} />
      <div className="mt-4 flex items-center gap-3">
        <Button type="submit" disabled={pending} className="h-9">
          {pending ? "Menyimpan..." : "Tambah produk"}
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

export function ProductEditForm({
  tenantId,
  categories,
  units,
  product,
}: BaseProps & { product: ProductRow }) {
  const [state, formAction, pending] = useActionState(
    updateProductAction,
    initialState
  );
  const [deleteState, deleteAction, deletePending] = useActionState(
    deleteProductAction,
    initialState
  );

  return (
    <div className="flex flex-col gap-4">
      <form action={formAction} className="rounded-lg border bg-card p-4">
        <input type="hidden" name="tenantId" value={tenantId} />
        <input type="hidden" name="id" value={product.id} />
        <ProductFields
          categories={categories}
          units={units}
          product={product}
        />

        <label className="mt-3 flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="active"
            defaultChecked={product.active}
            className="size-4"
          />
          Produk aktif
        </label>

        <div className="mt-4 flex items-center gap-3">
          <Button type="submit" disabled={pending} className="h-9">
            {pending ? "Menyimpan..." : "Simpan perubahan"}
          </Button>
          {state.error ? (
            <p className="text-sm text-destructive" role="alert">
              {state.error}
            </p>
          ) : null}
        </div>
      </form>

      <form action={deleteAction}>
        <input type="hidden" name="tenantId" value={tenantId} />
        <input type="hidden" name="id" value={product.id} />
        <Button
          type="submit"
          variant="destructive"
          disabled={deletePending}
          className="h-9"
        >
          {deletePending ? "Menghapus..." : "Hapus produk"}
        </Button>
        {deleteState.error ? (
          <p className="mt-2 text-sm text-destructive" role="alert">
            {deleteState.error}
          </p>
        ) : null}
      </form>
    </div>
  );
}

function ProductFields({
  categories,
  units,
  product,
}: {
  categories: CatalogItem[];
  units: CatalogItem[];
  product?: ProductRow;
}) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        <span className="font-medium">Nama produk</span>
        <input
          name="name"
          required
          maxLength={120}
          defaultValue={product?.name ?? ""}
          placeholder="cth: Oli Mesin 1L"
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Kategori</span>
        <select
          name="categoryId"
          defaultValue={product?.categoryId ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        >
          <option value="">— Tanpa kategori —</option>
          {categories.map((category) => (
            <option key={category.id} value={category.id}>
              {category.name}
            </option>
          ))}
        </select>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Satuan</span>
        <select
          name="baseUnitId"
          required
          defaultValue={product?.baseUnitId ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        >
          <option value="" disabled>
            Pilih satuan
          </option>
          {units.map((unit) => (
            <option key={unit.id} value={unit.id}>
              {unit.name}
            </option>
          ))}
        </select>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Jenis produk</span>
        <select
          name="kind"
          defaultValue={product?.kind ?? "barang"}
          className="h-9 rounded-md border border-input bg-background px-2"
        >
          <option value="barang">Barang</option>
          <option value="jasa">Jasa</option>
          <option value="paket">Paket</option>
        </select>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Harga jual (Rp)</span>
        <input
          name="sellPrice"
          type="number"
          min={0}
          step={1}
          required
          defaultValue={product?.sellPrice ?? 0}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Stok minimum</span>
        <input
          name="minStock"
          type="number"
          min={0}
          step={0.001}
          defaultValue={product?.minStock ?? 0}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">SKU (opsional)</span>
        <input
          name="sku"
          maxLength={40}
          defaultValue={product?.sku ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Barcode (opsional)</span>
        <input
          name="barcode"
          maxLength={60}
          defaultValue={product?.barcode ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>
    </div>
  );
}
