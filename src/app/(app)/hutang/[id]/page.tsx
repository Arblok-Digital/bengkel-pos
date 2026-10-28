import Link from "next/link";
import { notFound } from "next/navigation";

import { getPayableDetail, type PayableStatus } from "@/features/purchasing/queries";
import { formatRupiah } from "@/lib/money";
import { PayForm } from "./pay-form";

const statusBadge: Record<PayableStatus, { label: string; className: string }> = {
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

export default async function PayableDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const data = await getPayableDetail(id);

  if (!data) {
    notFound();
  }

  const { payments } = data;
  const badge = statusBadge[data.status];

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div className="flex items-center justify-between">
        <Link
          href="/hutang"
          className="text-sm font-medium text-muted-foreground hover:text-foreground"
        >
          &larr; Kembali ke Daftar Hutang
        </Link>
        {data.purchaseOrderId && data.poNo && (
          <Link
            href={`/pembelian/${data.purchaseOrderId}`}
            className="rounded-md border px-3 py-1.5 text-xs font-medium hover:bg-muted"
          >
            Lihat PO ({data.poNo})
          </Link>
        )}
      </div>

      <div className="rounded-lg border bg-card p-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-bold">Hutang #{data.supplierName}</h1>
              <span
                className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-semibold ${badge.className}`}
                data-testid="detail-status-badge"
              >
                {badge.label}
              </span>
            </div>
            <p className="mt-1 text-sm text-muted-foreground">
              Supplier: <strong className="text-foreground">{data.supplierName}</strong>
            </p>
          </div>

          <div className="text-right sm:text-right">
            <span className="text-xs text-muted-foreground">Jatuh Tempo:</span>
            <div className={`text-base font-bold ${data.remaining > 0 && new Date(data.dueDate) < new Date() ? "text-red-600" : ""}`}>
              {formatDate(data.dueDate)}
            </div>
            {data.remaining > 0 && new Date(data.dueDate) < new Date() ? (
              <span className="inline-block rounded bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-800">
                Lewat Jatuh Tempo
              </span>
            ) : null}
          </div>
        </div>

        <div className="mt-6 grid grid-cols-1 gap-4 border-t pt-4 sm:grid-cols-3">
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Total Hutang Supplier</span>
            <p className="mt-1 text-lg font-bold">{formatRupiah(data.amount)}</p>
          </div>
          <div className="rounded-md bg-emerald-50/50 p-3">
            <span className="text-xs text-emerald-700">Sudah Dibayar</span>
            <p className="mt-1 text-lg font-bold text-emerald-700">
              {formatRupiah(data.totalPaid)}
            </p>
          </div>
          <div className="rounded-md bg-amber-50/50 p-3">
            <span className="text-xs text-amber-700">Sisa Saldo Hutang</span>
            <p className="mt-1 text-xl font-black text-amber-700" data-testid="detail-remaining">
              {formatRupiah(data.remaining)}
            </p>
          </div>
        </div>
      </div>

      <PayForm
        tenantId={data.tenantId}
        payableId={data.id}
        remaining={data.remaining}
        isPaid={data.status === "paid"}
      />

      <div className="rounded-lg border bg-card p-6">
        <h2 className="text-base font-semibold">Riwayat Pembayaran Hutang</h2>
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="pb-2 font-medium">Waktu Bayar</th>
                <th className="pb-2 font-medium">Metode</th>
                <th className="pb-2 font-medium">Referensi</th>
                <th className="pb-2 font-medium text-right">Nominal</th>
              </tr>
            </thead>
            <tbody>
              {payments.length === 0 ? (
                <tr>
                  <td colSpan={4} className="py-4 text-center text-muted-foreground">
                    Belum ada pembayaran hutang.
                  </td>
                </tr>
              ) : (
                payments.map((p, idx) => (
                  <tr key={p.id} className="border-b last:border-b-0 hover:bg-muted/40" data-testid="payment-row">
                    <td className="py-3 font-medium">
                      <div>{formatDateTime(p.paidAt)}</div>
                      <div className="text-xs text-muted-foreground">Pembayaran #{idx + 1}</div>
                    </td>
                    <td className="py-3 uppercase text-xs font-semibold">{p.method}</td>
                    <td className="py-3 text-muted-foreground">{p.reference ?? "—"}</td>
                    <td className="py-3 text-right font-bold text-emerald-600">
                      {formatRupiah(p.amount)}
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
