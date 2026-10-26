"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  createOpnameAction,
  type OpnameActionState,
} from "@/features/inventory/actions";

const initialState: OpnameActionState = { error: null, success: null };

export function CreateOpnameForm({
  tenantId,
  outlets,
}: {
  tenantId: string;
  outlets: { id: string; name: string }[];
}) {
  const [state, formAction, pending] = useActionState(
    createOpnameAction,
    initialState
  );

  return (
    <form
      action={formAction}
      className="flex flex-col gap-2 rounded-lg border bg-card p-4 sm:flex-row sm:items-end"
    >
      <input type="hidden" name="tenantId" value={tenantId} />

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

      <label className="flex flex-1 flex-col gap-1 text-sm">
        <span className="font-medium">Catatan (opsional)</span>
        <input
          name="note"
          maxLength={500}
          placeholder="cth: opname akhir bulan"
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <Button type="submit" disabled={pending} className="h-9">
        {pending ? "Membuat..." : "Buat opname"}
      </Button>

      {state.error ? (
        <p className="w-full text-sm text-destructive" role="alert">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
