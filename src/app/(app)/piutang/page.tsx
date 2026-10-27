import Link from "next/link";
import { redirect } from "next/navigation";

import { getReceivablesPage, type ReceivableStatus } from "@/features/ar/queries";
import { formatRupiah } from "@/lib/money";

const statusBadge: Record<ReceivableStatus, { label: string; className: string }> = {
  open: { label: "Belum Bayar", className: "bg-red-50 text-red-700 border-red-200" },
  partial: { label: "Sebagian", className: "bg-amber-50 text-amber-700 border-amber-200" },
  paid: { label: "Lunas", className: "bg-emerald-50 text-emerald-700 border-emerald-200" },
};

function formatDate(dateStr: string): string {
  try {
    return new Intl.DateTimeFormat("id-ID", {
      dateStyle: "medium",
    }).format(new Date(dateStr));
  } catch {
    return dateStr;
  }
}

export default async function PiutangPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { status } = await searchParams;
  const data = await getReceivablesPage(status);

  if (!data) {
    redirect("/onboarding");
  }

  const { receivables, summary } = data;

  return (
    <div className="mx-auto flex max-w-6xl flex-col gap-6">
      <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold">Daftar Piutang Pelanggan</h1>
          <p className="text-muted-foreground text-sm">
            {data.tenantName} &middot; Kelola tagihan tempo, cicilan, dan kwitansi.
          </p>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div className="rounded-lg border bg-card p-4">
          <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
            Total Piutang
          </p>
          <p className="mt-1 text-xl font-bold">{formatRupiah(summary.totalAmount)}</p>
        </div>
        <div className="rounded-lg border bg-card p-4">
          <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
            Total Terbayar
          </p>
          <p className="mt-1 text-xl font-bold text-emerald-600">
            {formatRupiah(summary.totalPaid)}
          </p>
        </div>
        <div className="rounded-lg border bg-card p-4">
          <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
            Sisa Piutang Aktif
          </p>
          <p className="mt-1 text-xl font-bold text-amber-600">
            {formatRupiah(summary.totalRemaining)}
          </p>
        </div>
        <div className="rounded-lg border bg-card p-4">
          <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
            Lewat Jatuh Tempo
          </p>
          <p
            className={`mt-1 text-xl font-bold ${
              summary.countOverdue > 0 ? "text-red-600" : "text-muted-foreground"
            }`}
          >
            {summary.countOverdue} Tagihan
          </p>
        </div>
      </div>

      {/* Filter Tabs */}
      <div className="flex gap-2 border-b pb-2 text-sm">
        <Link
          href="/piutang"
          className={`rounded-md px-3 py-1.5 font-medium ${
            !status ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-muted"
          }`}
        >
          Semua ({data.receivables.length})
        </Link>
        <Link
          href="/piutang?status=open"
          className={`rounded-md px-3 py-1.5 font-medium ${
            status === "open"
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:bg-muted"
          }`}
        >
          Belum Bayar
        </Link>
        <Link
          href="/piutang?status=partial"
          className={`rounded-md px-3 py-1.5 font-medium ${
            status === "partial"
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:bg-muted"
          }`}
        >
          Sebagian
        </Link>
        <Link
          href="/piutang?status=paid"
          className={`rounded-md px-3 py-1.5 font-medium ${
            status === "paid"
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:bg-muted"
          }`}
        >
          Lunas
        </Link>
      </div>

      {/* Receivables Table */}
      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Invoice</th>
              <th className="p-3 font-medium">Pelanggan</th>
              <th className="p-3 font-medium">Jatuh Tempo</th>
              <th className="p-3 font-medium text-right">Total Piutang</th>
              <th className="p-3 font-medium text-right">Terbayar</th>
              <th className="p-3 font-medium text-right">Sisa</th>
              <th className="p-3 font-medium text-center">Status</th>
              <th className="p-3 font-medium text-center">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {receivables.length === 0 ? (
              <tr>
                <td colSpan={8} className="p-6 text-center text-muted-foreground">
                  Belum ada data piutang.
                </td>
              </tr>
            ) : (
              receivables.map((rec) => {
                const badge = statusBadge[rec.status];
                return (
                  <tr key={rec.id} className="border-b last:border-b-0 hover:bg-muted/50" data-testid="receivable-row">
                    <td className="p-3 font-mono font-medium">
                      <Link
                        href={`/penjualan/${rec.saleId}`}
                        className="text-primary hover:underline"
                      >
                        {rec.invoiceNo}
                      </Link>
                    </td>
                    <td className="p-3">
                      <div className="font-medium">{rec.customerName}</div>
                      {rec.customerPhone ? (
                        <div className="text-xs text-muted-foreground">{rec.customerPhone}</div>
                      ) : null}
                    </td>
                    <td className="p-3">
                      <div className={rec.isOverdue ? "font-semibold text-red-600" : ""}>
                        {formatDate(rec.dueDate)}
                      </div>
                      {rec.isOverdue ? (
                        <span className="inline-block rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-semibold text-red-800">
                          Lewat Tempo
                        </span>
                      ) : null}
                    </td>
                    <td className="p-3 text-right font-medium">{formatRupiah(rec.amount)}</td>
                    <td className="p-3 text-right text-emerald-600">{formatRupiah(rec.totalPaid)}</td>
                    <td className="p-3 text-right font-bold text-amber-600" data-testid="receivable-remaining">
                      {formatRupiah(rec.remaining)}
                    </td>
                    <td className="p-3 text-center">
                      <span
                        className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-semibold ${badge.className}`}
                        data-testid="receivable-status-badge"
                      >
                        {badge.label}
                      </span>
                    </td>
                    <td className="p-3 text-center">
                      <Link
                        href={`/piutang/${rec.id}`}
                        className="inline-flex h-9 items-center rounded-md border px-3 text-xs font-medium hover:bg-muted"
                        data-testid="btn-detail-piutang"
                      >
                        {rec.status === "paid" ? "Detail" : "Bayar Cicilan"}
                      </Link>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
