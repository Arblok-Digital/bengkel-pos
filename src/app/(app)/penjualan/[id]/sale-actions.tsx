"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  resolveSaleReviewAction,
  returnSaleAction,
  voidSaleAction,
  type SaleMutationState,
} from "@/features/sales/actions";
import type { SaleDetail } from "@/features/sales/queries";

const initialState: SaleMutationState = { error: null, success: null };

export function SaleActions({ detail }: { detail: SaleDetail }) {
  const [returnState, returnAction, returnPending] = useActionState(
    returnSaleAction,
    initialState
  );
  const [voidState, voidAction, voidPending] = useActionState(
    voidSaleAction,
    initialState
  );
  const [reviewState, reviewAction, reviewPending] = useActionState(
    resolveSaleReviewAction,
    initialState
  );

  const returnable = detail.items.filter((item) => item.remainingQty > 0);
  const needsReview = detail.status === "needs_review";
  const canVoid =
    detail.status !== "void" && !needsReview && detail.returns.length === 0;

  return (
    <div className="flex flex-col gap-4">
      {needsReview ? (
        <section className="rounded-lg border border-amber-600/40 bg-amber-50 p-4">
          <h2 className="text-lg font-semibold">Transaksi perlu review</h2>
          <p className="text-muted-foreground mt-1 text-sm">
            Transaksi dibuat saat offline dan tidak bisa diproses otomatis
            (stok/harga berubah). Setujui untuk memotong stok sekarang, atau
            batalkan bila barang tidak jadi dijual.
          </p>

          <form action={reviewAction} className="mt-3 flex flex-col gap-3">
            <input type="hidden" name="saleId" value={detail.id} />

            <label className="flex flex-col gap-1 text-sm">
              <span className="font-medium">Catatan review (opsional)</span>
              <textarea
                name="reason"
                rows={2}
                maxLength={300}
                placeholder="cth: stok sudah dihitung ulang, barang diambil besok"
                className="rounded-md border border-input bg-background p-2"
              />
            </label>

            <div className="flex flex-wrap items-center gap-3">
              <Button
                type="submit"
                name="action"
                value="accept"
                disabled={reviewPending}
                className="h-11"
              >
                {reviewPending ? "Memproses..." : "Setujui & potong stok"}
              </Button>
              <Button
                type="submit"
                name="action"
                value="void"
                variant="destructive"
                disabled={reviewPending}
                className="h-11"
              >
                Batalkan transaksi
              </Button>
              {reviewState.error ? (
                <p className="text-sm text-destructive" role="alert">
                  {reviewState.error}
                </p>
              ) : null}
              {reviewState.success ? (
                <p className="text-sm text-green-700" role="status">
                  {reviewState.success}
                </p>
              ) : null}
            </div>
          </form>
        </section>
      ) : null}

      {!needsReview && detail.status !== "void" && returnable.length > 0 ? (
        <section className="rounded-lg border bg-card p-4">
          <h2 className="text-lg font-semibold">Retur barang</h2>
          <p className="text-muted-foreground mt-1 text-sm">
            Isi qty yang dikembalikan. Stok produk yang melacak stok otomatis
            bertambah lewat movement.
          </p>

          <form action={returnAction} className="mt-3 flex flex-col gap-3">
            <input type="hidden" name="saleId" value={detail.id} />
            <input
              type="hidden"
              name="clientUuid"
              value={crypto.randomUUID()}
            />

            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-muted-foreground">
                    <th className="p-2 font-medium">Produk</th>
                    <th className="p-2 font-medium">Sisa bisa retur</th>
                    <th className="p-2 font-medium">Qty retur</th>
                  </tr>
                </thead>
                <tbody>
                  {detail.items.map((item) => (
                    <tr key={item.id} className="border-b last:border-0">
                      <td className="p-2">{item.name}</td>
                      <td className="p-2 whitespace-nowrap">
                        {item.remainingQty.toLocaleString("id-ID", {
                          maximumFractionDigits: 3,
                        })}{" "}
                        {item.unitName}
                      </td>
                      <td className="p-2">
                        <input
                          name={`ret_${item.id}`}
                          type="number"
                          min={0}
                          max={item.remainingQty}
                          step={0.001}
                          defaultValue={0}
                          disabled={item.remainingQty <= 0}
                          aria-label={`Qty retur ${item.name}`}
                          className="h-11 w-28 rounded-md border border-input bg-background px-2 disabled:opacity-50"
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <label className="flex flex-col gap-1 text-sm">
              <span className="font-medium">Alasan retur</span>
              <textarea
                name="reason"
                required
                minLength={3}
                maxLength={300}
                rows={2}
                placeholder="cth: barang rusak, salah kirim"
                className="rounded-md border border-input bg-background p-2"
              />
            </label>

            <div className="flex items-center gap-3">
              <Button type="submit" disabled={returnPending} className="h-11">
                {returnPending ? "Menyimpan..." : "Simpan retur"}
              </Button>
              {returnState.error ? (
                <p className="text-sm text-destructive" role="alert">
                  {returnState.error}
                </p>
              ) : null}
              {returnState.success ? (
                <p className="text-sm text-green-700" role="status">
                  {returnState.success}
                </p>
              ) : null}
            </div>
          </form>
        </section>
      ) : null}

      {canVoid ? (
        <section className="rounded-lg border border-destructive/40 bg-destructive/5 p-4">
          <h2 className="text-lg font-semibold">Void penjualan</h2>
          <p className="text-muted-foreground mt-1 text-sm">
            Void membatalkan seluruh transaksi dan mengembalikan stok. Tidak
            bisa dilakukan jika sudah ada retur.
          </p>

          <form action={voidAction} className="mt-3 flex flex-col gap-3">
            <input type="hidden" name="saleId" value={detail.id} />
            <input
              type="hidden"
              name="clientUuid"
              value={crypto.randomUUID()}
            />

            <label className="flex flex-col gap-1 text-sm">
              <span className="font-medium">Alasan void</span>
              <textarea
                name="reason"
                required
                minLength={3}
                maxLength={300}
                rows={2}
                placeholder="cth: salah input, pelanggan batal"
                className="rounded-md border border-input bg-background p-2"
              />
            </label>

            <div className="flex items-center gap-3">
              <Button
                type="submit"
                variant="destructive"
                disabled={voidPending}
                className="h-11"
              >
                {voidPending ? "Memproses..." : "Void penjualan"}
              </Button>
              {voidState.error ? (
                <p className="text-sm text-destructive" role="alert">
                  {voidState.error}
                </p>
              ) : null}
              {voidState.success ? (
                <p className="text-sm text-green-700" role="status">
                  {voidState.success}
                </p>
              ) : null}
            </div>
          </form>
        </section>
      ) : null}
    </div>
  );
}
