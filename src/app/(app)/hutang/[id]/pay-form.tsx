"use client";

import { useActionState, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  payPayableAction,
  type PayPayableActionState,
} from "@/features/purchasing/actions";
import { formatRupiah } from "@/lib/money";

const initialState: PayPayableActionState = {
  error: null,
  success: null,
};

export function PayForm({
  tenantId,
  payableId,
  remaining,
  isPaid,
}: {
  tenantId: string;
  payableId: string;
  remaining: number;
  isPaid: boolean;
}) {
  const [state, formAction, pending] = useActionState(payPayableAction, initialState);
  const [payAmount, setPayAmount] = useState<number | string>(
    remaining > 0 ? remaining : ""
  );

  if (isPaid) {
    return (
      <div className="rounded-lg border border-emerald-200 bg-emerald-50 p-4 text-emerald-800">
        <p className="font-semibold">Hutang ini sudah lunas!</p>
        <p className="text-xs mt-1">Tidak ada sisa hutang yang harus dibayar.</p>
      </div>
    );
  }

  return (
    <form action={formAction} className="rounded-lg border bg-card p-4 flex flex-col gap-4">
      <input type="hidden" name="tenantId" value={tenantId} />
      <input type="hidden" name="payableId" value={payableId} />
      <input type="hidden" name="clientUuid" defaultValue={crypto.randomUUID()} />

      <h2 className="text-base font-semibold">Form Pembayaran Hutang</h2>

      {state.error ? (
        <div className="rounded-md border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive" role="alert">
          {state.error}
        </div>
      ) : null}

      {state.success ? (
        <div className="rounded-md border border-emerald-300 bg-emerald-50 p-3 text-sm text-emerald-800 flex flex-col gap-2">
          <p className="font-medium">
            Pembayaran berhasil dicatat! Sisa hutang:{" "}
            <strong>{formatRupiah(state.success.totalPaid >= state.success.amount ? state.success.totalPaid : remaining - state.success.amount)}</strong>
          </p>
        </div>
      ) : null}

      <div className="space-y-1">
        <label className="text-sm font-medium" htmlFor="amount">
          Nominal Pembayaran (Rp)
        </label>
        <div className="flex gap-2">
          <input
            id="amount"
            name="amount"
            type="number"
            min={1}
            max={remaining}
            value={payAmount}
            onChange={(e) => setPayAmount(e.target.value)}
            required
            className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
            data-testid="input-pay-amount"
          />
          <button
            type="button"
            onClick={() => setPayAmount(remaining)}
            className="whitespace-nowrap rounded-md border px-3 text-xs font-medium hover:bg-muted"
          >
            Lunas ({formatRupiah(remaining)})
          </button>
        </div>
        <p className="text-xs text-muted-foreground">
          Maksimal pembayaran: {formatRupiah(remaining)}
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="space-y-1">
          <label className="text-sm font-medium" htmlFor="method">
            Metode Pembayaran
          </label>
          <select
            id="method"
            name="method"
            defaultValue="tunai"
            className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
            data-testid="select-pay-method"
          >
            <option value="tunai">Tunai</option>
            <option value="transfer">Transfer Bank</option>
            <option value="qris">QRIS</option>
            <option value="debit">Debit</option>
          </select>
        </div>

        <div className="space-y-1">
          <label className="text-sm font-medium" htmlFor="reference">
            No. Referensi / Bukti (Opsional)
          </label>
          <input
            id="reference"
            name="reference"
            type="text"
            placeholder="Contoh: TRF-BCA-123"
            className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
            data-testid="input-pay-reference"
          />
        </div>
      </div>

      <div className="pt-2">
        <Button
          type="submit"
          disabled={pending || remaining <= 0}
          className="h-10 w-full sm:w-auto"
          data-testid="btn-submit-payment"
        >
          {pending ? "Memproses Pembayaran..." : "Simpan Pembayaran"}
        </Button>
      </div>
    </form>
  );
}
