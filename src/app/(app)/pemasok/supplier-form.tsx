"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  createSupplierAction,
  deleteSupplierAction,
  updateSupplierAction,
  type SupplierActionState,
} from "@/features/suppliers/actions";
import type { SupplierRow } from "@/features/suppliers/queries";

const initialState: SupplierActionState = { error: null };

export function SupplierCreateForm({ tenantId }: { tenantId: string }) {
  const [state, formAction, pending] = useActionState(
    createSupplierAction,
    initialState
  );

  return (
    <form action={formAction} className="rounded-lg border bg-card p-4">
      <input type="hidden" name="tenantId" value={tenantId} />
      <SupplierFields />
      <div className="mt-4 flex items-center gap-3">
        <Button type="submit" disabled={pending} className="h-9">
          {pending ? "Menyimpan..." : "Tambah pemasok"}
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

export function SupplierEditForm({
  tenantId,
  supplier,
}: {
  tenantId: string;
  supplier: SupplierRow;
}) {
  const [state, formAction, pending] = useActionState(
    updateSupplierAction,
    initialState
  );
  const [deleteState, deleteAction, deletePending] = useActionState(
    deleteSupplierAction,
    initialState
  );

  return (
    <div className="flex flex-col gap-4">
      <form action={formAction} className="rounded-lg border bg-card p-4">
        <input type="hidden" name="tenantId" value={tenantId} />
        <input type="hidden" name="id" value={supplier.id} />
        <SupplierFields supplier={supplier} />

        <label className="mt-3 flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="active"
            defaultChecked={supplier.active}
            className="size-4"
          />
          Pemasok aktif
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
        <input type="hidden" name="id" value={supplier.id} />
        <Button
          type="submit"
          variant="destructive"
          disabled={deletePending}
          className="h-9"
        >
          {deletePending ? "Menghapus..." : "Hapus pemasok"}
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

function SupplierFields({ supplier }: { supplier?: SupplierRow }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Nama pemasok</span>
        <input
          name="name"
          required
          maxLength={120}
          defaultValue={supplier?.name ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">No. HP</span>
        <input
          name="phone"
          maxLength={30}
          defaultValue={supplier?.phone ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        <span className="font-medium">Alamat</span>
        <input
          name="address"
          maxLength={300}
          defaultValue={supplier?.address ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Termin pembayaran (hari)</span>
        <input
          name="paymentTermsDays"
          type="number"
          min={0}
          max={3650}
          step={1}
          defaultValue={supplier?.paymentTermsDays ?? 0}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>
    </div>
  );
}
