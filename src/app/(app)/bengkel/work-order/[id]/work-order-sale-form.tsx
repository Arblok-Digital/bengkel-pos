"use client";

import { useActionState, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  convertWorkOrderToSaleAction,
  type WorkOrderActionState,
} from "@/features/workorder/actions";
import { formatRupiah } from "@/lib/money";

const initialState: WorkOrderActionState = { error: null };

type PaymentMethod = "tunai" | "transfer" | "qris" | "debit" | "kredit_tempo";

const paymentLabels: Record<PaymentMethod, string> = {
  tunai: "Tunai",
  transfer: "Transfer",
  qris: "QRIS",
  debit: "Debit",
  kredit_tempo: "Kredit / tempo",
};

export function WorkOrderSaleForm({
  workOrderId,
  estimatedTotal,
}: {
  workOrderId: string;
  estimatedTotal: number;
}) {
  const [state, formAction, pending] = useActionState(
    convertWorkOrderToSaleAction,
    initialState
  );
  const [clientUuid] = useState(() => crypto.randomUUID());
  const [method, setMethod] = useState<PaymentMethod>("tunai");
  const [amount, setAmount] = useState(
    estimatedTotal > 0 ? String(estimatedTotal) : ""
  );

  const isKredit = method === "kredit_tempo";
  const paymentAmount = isKredit ? String(estimatedTotal) : amount;

  return (
    <section className="rounded-lg border border-primary/30 bg-primary/5 p-5">
      <h2 className="text-lg font-semibold">Tagihkan Work Order</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        Item work order akan dibuat sebagai satu transaksi penjualan. Harga dan stok
        divalidasi ulang oleh server saat disimpan.
      </p>

      <form action={formAction} className="mt-4 grid gap-4 sm:grid-cols-2">
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="clientUuid" value={clientUuid} />
        <input type="hidden" name="paymentAmount" value={paymentAmount} />

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Metode pembayaran</span>
          <select
            name="paymentMethod"
            value={method}
            onChange={(event) => setMethod(event.target.value as PaymentMethod)}
            className="min-h-11 rounded-md border border-input bg-background px-3"
          >
            {(Object.keys(paymentLabels) as PaymentMethod[]).map((value) => (
              <option key={value} value={value}>
                {paymentLabels[value]}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">
            {isKredit ? "Nilai kredit / tempo" : "Nominal pembayaran"}
          </span>
          <input
            type="number"
            min="1"
            step="1"
            required
            value={paymentAmount}
            onChange={(event) => setAmount(event.target.value)}
            readOnly={isKredit}
            disabled={isKredit}
            aria-label={isKredit ? "Nilai kredit / tempo" : "Nominal pembayaran"}
            className="min-h-11 rounded-md border border-input bg-background px-3 read-only:bg-muted"
          />
          <span className="text-xs text-muted-foreground">
            {isKredit
              ? "Piutang dicatat penuh sebesar total work order."
              : `Estimasi work order: ${formatRupiah(estimatedTotal)}`}
          </span>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Referensi pembayaran (opsional)</span>
          <input
            name="paymentReference"
            maxLength={100}
            placeholder="cth: QRIS-12345"
            className="min-h-11 rounded-md border border-input bg-background px-3"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Catatan transaksi (opsional)</span>
          <input
            name="note"
            maxLength={500}
            placeholder="Catatan untuk nota"
            className="min-h-11 rounded-md border border-input bg-background px-3"
          />
        </label>

        <div className="sm:col-span-2 flex flex-wrap items-center gap-3">
          <Button type="submit" disabled={pending} className="min-h-11 px-4">
            {pending ? "Menyimpan penjualan..." : "Buat penjualan & buka nota"}
          </Button>
          {state.error ? (
            <p className="text-sm text-destructive" role="alert">
              {state.error}
            </p>
          ) : null}
        </div>
      </form>
    </section>
  );
}