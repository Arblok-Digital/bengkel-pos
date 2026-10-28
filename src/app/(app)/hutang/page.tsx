import Link from "next/link";
import { redirect } from "next/navigation";

import { getPayablesPage, type PayableStatus } from "@/features/purchasing/queries";
import { formatRupiah } from "@/lib/money";

const statusBadge: Record<PayableStatus, { label: string; className: string }> = {
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

export default async function PayablesPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { status } = await searchParams;
  const data = await getPayablesPage(status);

  if (!data) {
    redirect("/onboarding");
  }

  const { payables, summary } = data;

  return (
    <div className="mx-auto flex max-w-6xl flex-col gap-6">
      <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold">Daftar Hutang Supplier</h1>
          <p className="text-muted-foreground text-sm">
            {data.tenantName} &middot; Kelola hutang dagang dan pembayaran cicilan.
          </p>
        </div>
        {data.canWrite ? (
          <Link
            href="/hutang/buat"
            className="rounded-md border bg-primary px-4 py-2 text-sm text-primary-foreground hover:bg-primary/90 transition"
          >
            Catat Hutang Baru
          </Link>
        ) : null}
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div className="rounded-lg border bg-card p-4">
          <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
            Total Hutang
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
            Sisa Hutang Aktif
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
            {summary.countOverdue} Hutang
          </p>
        </div>
      </div>

      <div className="flex gap-2 border-b pb-2 text-sm">
        <Link
          href="/hutang"
          className={`rounded-md px-3 py-1.5 font-medium ${
            !status ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-muted"
          }`}
        >
          Semua ({data.payables.length})
        </Link>
        <Link
          href="/hutang?status=open"
          className={`rounded-md px-3 py-1.5 font-medium ${
            status === "open"
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:bg-muted"
          }`}
        >
          Belum Bayar
        </Link>
        <Link
          href="/hutang?status=partial"
          className={`rounded-md px-3 py-1.5 font-medium ${
            status === "partial"
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:bg-muted"
          }`}
        >
          Sebagian
        </Link>
        <Link
          href="/hutang?status=paid"
          className={`rounded-md px-3 py-1.5 font-medium ${
            status === "paid"
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:bg-muted"
          }`}
        >
          Lunas
        </Link>
      </div>

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Supplier</th>
              <th className="p-3 font-medium">PO</th>
              <th className="p-3 font-medium">Jatuh Tempo</th>
              <th className="p-3 font-medium text-right">Total Hutang</th>
              <th className="p-3 font-medium text-right">Terbayar</th>
              <th className="p-3 font-medium text-right">Sisa</th>
              <th className="p-3 font-medium text-center">Status</th>
              <th className="p-3 font-medium text-center">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {payables.length === 0 ? (
              <tr>
                <td colSpan={8} className="p-6 text-center text-muted-foreground">
                  Belum ada data hutang.
                </td>
              </tr>
            ) : (
              payables.map((pay) => {
                const badge = statusBadge[pay.status];
                return (
                  <tr
                    key={pay.id}
                    className="border-b last:border-b-0 hover:bg-muted/50"
                    data-testid="payable-row"
                  >
                    <td className="p-3 font-medium">{pay.supplierName}</td>
                    <td className="p-3">{pay.poNo ?? "—"}</td>
                    <td className="p-3">
                      <div className={pay.remaining > 0 && new Date(pay.dueDate) < new Date() ? "font-semibold text-red-600" : ""}>
                        {formatDate(pay.dueDate)}
                      </div>
                    </td>
                    <td className="p-3 text-right font-medium">
                      {formatRupiah(pay.amount)}
                    </td>
                    <td className="p-3 text-right text-emerald-600">
                      {formatRupiah(pay.totalPaid)}
                    </td>
                    <td className="p-3 text-right font-bold text-amber-600">
                      {formatRupiah(pay.remaining)}
                    </td>
                    <td className="p-3 text-center">
                      <span
                        className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-semibold ${badge.className}`}
                      >
                        {badge.label}
                      </span>
                    </td>
                    <td className="p-3 text-center">
                      <Link
                        href={`/hutang/${pay.id}`}
                        className="inline-flex h-9 items-center rounded-md border px-3 text-xs font-medium hover:bg-muted"
                      >
                        {pay.status === "paid" ? "Detail" : "Bayar Cicilan"}
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
