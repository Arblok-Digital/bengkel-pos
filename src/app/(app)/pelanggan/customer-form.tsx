"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  createCustomerAction,
  deleteCustomerAction,
  updateCustomerAction,
  type CustomerActionState,
} from "@/features/customers/actions";
import type {
  CustomerRow,
  CustomerTier,
} from "@/features/customers/queries";

const initialState: CustomerActionState = { error: null };

export function CustomerCreateForm({
  tenantId,
  tiers,
}: {
  tenantId: string;
  tiers: CustomerTier[];
}) {
  const [state, formAction, pending] = useActionState(
    createCustomerAction,
    initialState
  );

  return (
    <form action={formAction} className="rounded-lg border bg-card p-4">
      <input type="hidden" name="tenantId" value={tenantId} />
      <CustomerFields tiers={tiers} />
      <div className="mt-4 flex items-center gap-3">
        <Button type="submit" disabled={pending} className="h-9">
          {pending ? "Menyimpan..." : "Tambah pelanggan"}
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

export function CustomerEditForm({
  tenantId,
  tiers,
  customer,
}: {
  tenantId: string;
  tiers: CustomerTier[];
  customer: CustomerRow;
}) {
  const [state, formAction, pending] = useActionState(
    updateCustomerAction,
    initialState
  );
  const [deleteState, deleteAction, deletePending] = useActionState(
    deleteCustomerAction,
    initialState
  );

  return (
    <div className="flex flex-col gap-4">
      <form action={formAction} className="rounded-lg border bg-card p-4">
        <input type="hidden" name="tenantId" value={tenantId} />
        <input type="hidden" name="id" value={customer.id} />
        <CustomerFields tiers={tiers} customer={customer} />

        <label className="mt-3 flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="active"
            defaultChecked={customer.active}
            className="size-4"
          />
          Pelanggan aktif
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
        <input type="hidden" name="id" value={customer.id} />
        <Button
          type="submit"
          variant="destructive"
          disabled={deletePending}
          className="h-9"
        >
          {deletePending ? "Menghapus..." : "Hapus pelanggan"}
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

function CustomerFields({
  tiers,
  customer,
}: {
  tiers: CustomerTier[];
  customer?: CustomerRow;
}) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Nama pelanggan</span>
        <input
          name="name"
          required
          maxLength={120}
          defaultValue={customer?.name ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">No. HP</span>
        <input
          name="phone"
          maxLength={30}
          defaultValue={customer?.phone ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        <span className="font-medium">Alamat</span>
        <input
          name="address"
          maxLength={300}
          defaultValue={customer?.address ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Tier harga</span>
        <select
          name="tierId"
          defaultValue={customer?.tierId ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        >
          <option value="">— Tanpa tier (Umum) —</option>
          {tiers.map((tier) => (
            <option key={tier.id} value={tier.id}>
              {tier.name}
            </option>
          ))}
        </select>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Limit kredit (Rp)</span>
        <input
          name="creditLimit"
          type="number"
          min={0}
          step={1}
          defaultValue={customer?.creditLimit ?? 0}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        <span className="font-medium">Catatan</span>
        <input
          name="notes"
          maxLength={500}
          defaultValue={customer?.notes ?? ""}
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>
    </div>
  );
}
