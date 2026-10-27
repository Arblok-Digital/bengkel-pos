import Link from "next/link";
import { notFound } from "next/navigation";

import { getReceivableDetail, type ReceivableStatus } from "@/features/ar/queries";
import { formatRupiah } from "@/lib/money";
import { PayForm } from "./pay-form";

const statusBadge: Record<ReceivableStatus, { label: string; className: string }> = {
  open: { label: "Belum Bayar", className: "bg-red-50 text-red-700 border-red-200" },
  partial: { label: "Sebagian", className: "bg-amber-50 text-amber-700 border-amber-200" },
  paid: { label: "Lunas", className: "bg-emerald-50 text-emerald-700 border-emerald-200" },
};

function formatDateTime(value: string): string {
  try {
    return new Intl.DateTimeFormat("id-ID", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(value));
  } catch {
    return value;
  }
}

function formatDate(dateStr: string): string {
  try {
    return new Intl.DateTimeFormat("id-ID", {
      dateStyle: "medium",
    }).format(new Date(dateStr));
  } catch {
    return dateStr;
  }
}

export default async function ReceivableDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const data = await getReceivableDetail(id);

  if (!data) {
    notFound();
  }

  const { receivable, sale, customer, payments } = data;
  const badge = statusBadge[receivable.status];

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div className="flex items-center justify-between">
        <Link
          href="/piutang"
          className="text-sm font-medium text-muted-foreground hover:text-foreground"
        >
          &larr; Kembali ke Daftar Piutang
        </Link>
        <div className="flex items-center gap-2">
          <Link
            href={`/penjualan/${sale.id}`}
            className="rounded-md border px-3 py-1.5 text-xs font-medium hover:bg-muted"
          >
            Lihat Struk Penjualan ({sale.invoiceNo})
          </Link>
        </div>
      </div>

      {/* Header & Status */}
      <div className="rounded-lg border bg-card p-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-bold">Piutang #{sale.invoiceNo}</h1>
              <span
                className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-semibold ${badge.className}`}
                data-testid="detail-status-badge"
              >
                {badge.label}
              </span>
            </div>
            <p className="mt-1 text-sm text-muted-foreground">
              Pelanggan: <strong className="text-foreground">{customer.name}</strong>
              {customer.phone ? ` (${customer.phone})` : ""}
            </p>
          </div>

          <div className="text-right sm:text-right">
            <span className="text-xs text-muted-foreground">Jatuh Tempo:</span>
            <div className={`text-base font-bold ${receivable.isOverdue ? "text-red-600" : ""}`}>
              {formatDate(receivable.dueDate)}
            </div>
            {receivable.isOverdue ? (
              <span className="inline-block rounded bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-800">
                Lewat Jatuh Tempo
              </span>
            ) : null}
          </div>
        </div>

        {/* Financial Breakdown */}
        <div className="mt-6 grid grid-cols-1 gap-4 border-t pt-4 sm:grid-cols-3">
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Total Tagihan Piutang</span>
            <p className="mt-1 text-lg font-bold">{formatRupiah(receivable.amount)}</p>
          </div>
          <div className="rounded-md bg-emerald-50/50 p-3">
            <span className="text-xs text-emerald-700">Sudah Dibayar</span>
            <p className="mt-1 text-lg font-bold text-emerald-700">
              {formatRupiah(receivable.totalPaid)}
            </p>
          </div>
          <div className="rounded-md bg-amber-50/50 p-3">
            <span className="text-xs text-amber-700">Sisa Saldo Piutang</span>
            <p className="mt-1 text-xl font-black text-amber-700" data-testid="detail-remaining">
              {formatRupiah(receivable.remaining)}
            </p>
          </div>
        </div>
      </div>

      {/* Pay Form Component */}
      <PayForm
        tenantId={receivable.tenantId}
        receivableId={receivable.id}
        remaining={receivable.remaining}
        isPaid={receivable.status === "paid"}
      />

      {/* Payment History */}
      <div className="rounded-lg border bg-card p-6">
        <h2 className="text-base font-semibold">Riwayat Pembayaran Cicilan</h2>
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="pb-2 font-medium">Waktu Bayar</th>
                <th className="pb-2 font-medium">Metode</th>
                <th className="pb-2 font-medium">Referensi</th>
                <th className="pb-2 font-medium text-right">Nominal</th>
                <th className="pb-2 font-medium text-center">Kwitansi</th>
              </tr>
            </thead>
            <tbody>
              {payments.length === 0 ? (
                <tr>
                  <td colSpan={5} className="py-4 text-center text-muted-foreground">
                    Belum ada pembayaran cicilan.
                  </td>
                </tr>
              ) : (
                payments.map((p, idx) => (
                  <tr key={p.id} className="border-b last:border-b-0 hover:bg-muted/40" data-testid="payment-row">
                    <td className="py-3 font-medium">
                      <div>{formatDateTime(p.paidAt)}</div>
                      <div className="text-xs text-muted-foreground">Cicilan #{idx + 1}</div>
                    </td>
                    <td className="py-3 uppercase text-xs font-semibold">{p.method}</td>
                    <td className="py-3 text-muted-foreground">{p.reference ?? "—"}</td>
                    <td className="py-3 text-right font-bold text-emerald-600">
                      {formatRupiah(p.amount)}
                    </td>
                    <td className="py-3 text-center">
                      <Link
                        href={`/piutang/${receivable.id}/kwitansi?paymentId=${p.id}`}
                        className="inline-flex h-8 items-center rounded border px-2.5 text-xs font-medium hover:bg-muted"
                        data-testid="link-kwitansi"
                      >
                        Cetak
                      </Link>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
