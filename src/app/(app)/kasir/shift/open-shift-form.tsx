"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  openShiftAction,
  type ShiftActionState,
} from "@/features/shifts/actions";

const initialState: ShiftActionState = { error: null };

export function OpenShiftForm({
  tenantId,
  outlets,
  clientUuid,
}: {
  tenantId: string;
  outlets: { id: string; name: string }[];
  clientUuid: string;
}) {
  const [state, formAction, pending] = useActionState(
    openShiftAction,
    initialState
  );

  return (
    <form action={formAction} className="mt-4 grid gap-3">
      <input type="hidden" name="tenantId" value={tenantId} />
      <input type="hidden" name="clientUuid" value={clientUuid} />

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Outlet</span>
        <select
          name="outletId"
          required
          defaultValue={outlets[0]?.id ?? ""}
          className="h-11 rounded-md border border-input bg-background px-2"
        >
          {outlets.map((outlet) => (
            <option key={outlet.id} value={outlet.id}>
              {outlet.name}
            </option>
          ))}
        </select>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Modal awal (Rp)</span>
        <input
          name="openingCash"
          type="number"
          inputMode="numeric"
          min={0}
          step={1}
          required
          defaultValue={0}
          className="h-11 rounded-md border border-input bg-background px-3 text-lg"
        />
        <span className="text-muted-foreground text-xs">
          Uang tunai di laci saat shift dimulai.
        </span>
      </label>

      <div className="flex items-center gap-3">
        <Button type="submit" disabled={pending} className="h-11 min-w-44">
          {pending ? "Membuka..." : "Buka kasir"}
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
