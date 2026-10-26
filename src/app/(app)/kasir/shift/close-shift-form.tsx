"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  closeShiftAction,
  type ShiftActionState,
} from "@/features/shifts/actions";

const initialState: ShiftActionState = { error: null };

export function CloseShiftForm({
  tenantId,
  shiftId,
  clientUuid,
}: {
  tenantId: string;
  shiftId: string;
  clientUuid: string;
}) {
  const [state, formAction, pending] = useActionState(
    closeShiftAction,
    initialState
  );

  return (
    <form action={formAction} className="mt-3 grid gap-3">
      <input type="hidden" name="tenantId" value={tenantId} />
      <input type="hidden" name="shiftId" value={shiftId} />
      <input type="hidden" name="clientUuid" value={clientUuid} />

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Uang tunai dihitung (Rp)</span>
        <input
          name="closingCashCounted"
          type="number"
          inputMode="numeric"
          min={0}
          step={1}
          required
          className="h-11 rounded-md border border-input bg-background px-3 text-lg"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Catatan (opsional)</span>
        <input
          name="note"
          maxLength={500}
          placeholder="cth: selisih karena kembalian"
          className="h-11 rounded-md border border-input bg-background px-3"
        />
      </label>

      <div className="flex items-center gap-3">
        <Button
          type="submit"
          variant="destructive"
          disabled={pending}
          className="h-11 min-w-44"
        >
          {pending ? "Menutup..." : "Tutup kasir"}
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
