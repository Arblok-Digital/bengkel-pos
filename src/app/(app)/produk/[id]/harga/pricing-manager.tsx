"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  addPriceBreakAction,
  addProductUnitAction,
  deletePriceBreakAction,
  deleteProductPriceAction,
  deleteProductUnitAction,
  upsertProductPriceAction,
  type PricingActionState,
} from "@/features/catalog/pricing-actions";
import type { PricingData } from "@/features/catalog/queries";
import { formatRupiah } from "@/lib/money";

const initialState: PricingActionState = { error: null, success: null };

type DeleteAction = (
  prev: PricingActionState,
  formData: FormData
) => Promise<PricingActionState>;

export function PricingManager({ data }: { data: PricingData }) {
  return (
    <div className="flex flex-col gap-6">
      <ProductUnitsSection data={data} />
      <TierPricesSection data={data} />
      <PriceBreaksSection data={data} />
    </div>
  );
}

function ProductUnitsSection({ data }: { data: PricingData }) {
  const [state, formAction, pending] = useActionState(
    addProductUnitAction,
    initialState
  );
  const availableUnits = data.units.filter(
    (unit) => unit.id !== data.product.baseUnitId
  );

  return (
    <section className="rounded-lg border bg-card p-4">
      <h2 className="text-lg font-semibold">Satuan tambahan</h2>
      <p className="text-muted-foreground mt-1 text-sm">
        Contoh: 1 sak = 40 kg. Harga di sini dipakai untuk satuan tersebut.
      </p>

      <form
        action={formAction}
        className="mt-3 flex flex-col gap-2 sm:flex-row sm:items-end"
      >
        <input type="hidden" name="tenantId" value={data.tenantId} />
        <input type="hidden" name="productId" value={data.product.id} />
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Satuan</span>
          <select
            name="unitId"
            required
            defaultValue=""
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="" disabled>
              Pilih satuan
            </option>
            {availableUnits.map((unit) => (
              <option key={unit.id} value={unit.id}>
                {unit.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Faktor ke satuan dasar</span>
          <input
            name="factorToBase"
            type="number"
            min={0.0001}
            step={0.0001}
            required
            placeholder="40"
            className="h-9 w-32 rounded-md border border-input bg-background px-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Harga (Rp)</span>
          <input
            name="sellPrice"
            type="number"
            min={0}
            step={1}
            required
            className="h-9 w-32 rounded-md border border-input bg-background px-2"
          />
        </label>
        <Button type="submit" disabled={pending} className="h-9">
          {pending ? "Menyimpan..." : "Tambah satuan"}
        </Button>
      </form>

      {state.error ? (
        <p className="mt-2 text-sm text-destructive" role="alert">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p className="mt-2 text-sm text-green-700" role="status">
          {state.success}
        </p>
      ) : null}

      <div className="mt-3">
        {data.productUnits.length === 0 ? (
          <p className="text-muted-foreground text-sm">Belum ada satuan tambahan.</p>
        ) : (
          data.productUnits.map((row) => (
            <div
              key={row.id}
              className="flex items-center justify-between gap-3 border-b py-2 text-sm last:border-0"
            >
              <span>
                1 {row.unitName} = {row.factorToBase}{" "}
                {data.product.unitName ?? "satuan dasar"} &middot;{" "}
                {formatRupiah(row.sellPrice)}
              </span>
              <DeleteRow
                action={deleteProductUnitAction}
                tenantId={data.tenantId}
                productId={data.product.id}
                id={row.id}
                label="Hapus satuan"
              />
            </div>
          ))
        )}
      </div>
    </section>
  );
}

function TierPricesSection({ data }: { data: PricingData }) {
  const [state, formAction, pending] = useActionState(
    upsertProductPriceAction,
    initialState
  );

  return (
    <section className="rounded-lg border bg-card p-4">
      <h2 className="text-lg font-semibold">Harga per tier</h2>
      <p className="text-muted-foreground mt-1 text-sm">
        Harga tier menimpa harga satuan untuk unit yang sama.
      </p>

      <form
        action={formAction}
        className="mt-3 flex flex-col gap-2 sm:flex-row sm:items-end"
      >
        <input type="hidden" name="tenantId" value={data.tenantId} />
        <input type="hidden" name="productId" value={data.product.id} />
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Tier</span>
          <select
            name="tierId"
            required
            defaultValue=""
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="" disabled>
              Pilih tier
            </option>
            {data.tiers.map((tier) => (
              <option key={tier.id} value={tier.id}>
                {tier.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Satuan</span>
          <select
            name="unitId"
            required
            defaultValue={data.product.baseUnitId ?? ""}
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            {data.units.map((unit) => (
              <option key={unit.id} value={unit.id}>
                {unit.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Harga (Rp)</span>
          <input
            name="price"
            type="number"
            min={0}
            step={1}
            required
            className="h-9 w-32 rounded-md border border-input bg-background px-2"
          />
        </label>
        <Button type="submit" disabled={pending} className="h-9">
          {pending ? "Menyimpan..." : "Simpan harga tier"}
        </Button>
      </form>

      {state.error ? (
        <p className="mt-2 text-sm text-destructive" role="alert">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p className="mt-2 text-sm text-green-700" role="status">
          {state.success}
        </p>
      ) : null}

      <div className="mt-3 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="py-2 pr-3 font-medium">Tier</th>
              <th className="py-2 pr-3 font-medium">Satuan</th>
              <th className="py-2 pr-3 font-medium">Harga</th>
              <th className="py-2 font-medium">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {data.tierPrices.length === 0 ? (
              <tr>
                <td colSpan={4} className="text-muted-foreground py-2">
                  Belum ada harga tier.
                </td>
              </tr>
            ) : (
              data.tierPrices.map((row) => (
                <tr key={row.id} className="border-b last:border-0">
                  <td className="py-2 pr-3">{row.tierName}</td>
                  <td className="py-2 pr-3">{row.unitName}</td>
                  <td className="py-2 pr-3">{formatRupiah(row.price)}</td>
                  <td className="py-2">
                    <DeleteRow
                      action={deleteProductPriceAction}
                      tenantId={data.tenantId}
                      productId={data.product.id}
                      id={row.id}
                      label="Hapus harga tier"
                    />
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function PriceBreaksSection({ data }: { data: PricingData }) {
  const [state, formAction, pending] = useActionState(
    addPriceBreakAction,
    initialState
  );

  return (
    <section className="rounded-lg border bg-card p-4">
      <h2 className="text-lg font-semibold">Harga grosir</h2>
      <p className="text-muted-foreground mt-1 text-sm">
        Harga terendah yang berlaku untuk qty tertentu (setelah harga tier).
      </p>

      <form
        action={formAction}
        className="mt-3 flex flex-col gap-2 sm:flex-row sm:items-end"
      >
        <input type="hidden" name="tenantId" value={data.tenantId} />
        <input type="hidden" name="productId" value={data.product.id} />
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Satuan</span>
          <select
            name="unitId"
            required
            defaultValue={data.product.baseUnitId ?? ""}
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            {data.units.map((unit) => (
              <option key={unit.id} value={unit.id}>
                {unit.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Minimal qty</span>
          <input
            name="minQty"
            type="number"
            min={0.0001}
            step={0.0001}
            required
            className="h-9 w-32 rounded-md border border-input bg-background px-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Harga (Rp)</span>
          <input
            name="price"
            type="number"
            min={0}
            step={1}
            required
            className="h-9 w-32 rounded-md border border-input bg-background px-2"
          />
        </label>
        <Button type="submit" disabled={pending} className="h-9">
          {pending ? "Menyimpan..." : "Tambah harga grosir"}
        </Button>
      </form>

      {state.error ? (
        <p className="mt-2 text-sm text-destructive" role="alert">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p className="mt-2 text-sm text-green-700" role="status">
          {state.success}
        </p>
      ) : null}

      <div className="mt-3">
        {data.priceBreaks.length === 0 ? (
          <p className="text-muted-foreground text-sm">Belum ada harga grosir.</p>
        ) : (
          data.priceBreaks.map((row) => (
            <div
              key={row.id}
              className="flex items-center justify-between gap-3 border-b py-2 text-sm last:border-0"
            >
              <span>
                ≥ {row.minQty} {row.unitName} &middot; {formatRupiah(row.price)}
              </span>
              <DeleteRow
                action={deletePriceBreakAction}
                tenantId={data.tenantId}
                productId={data.product.id}
                id={row.id}
                label="Hapus harga grosir"
              />
            </div>
          ))
        )}
      </div>
    </section>
  );
}

function DeleteRow({
  action,
  tenantId,
  productId,
  id,
  label,
}: {
  action: DeleteAction;
  tenantId: string;
  productId: string;
  id: string;
  label: string;
}) {
  const [state, formAction, pending] = useActionState(action, initialState);

  return (
    <span className="flex flex-col items-end gap-1">
      <form action={formAction}>
        <input type="hidden" name="tenantId" value={tenantId} />
        <input type="hidden" name="productId" value={productId} />
        <input type="hidden" name="id" value={id} />
        <Button
          type="submit"
          variant="destructive"
          size="sm"
          disabled={pending}
          aria-label={label}
        >
          Hapus
        </Button>
      </form>
      {state.error ? (
        <span className="text-destructive" role="alert">
          {state.error}
        </span>
      ) : null}
    </span>
  );
}
