import Link from "next/link";
import { redirect } from "next/navigation";

import { getRecentSales } from "@/features/sales/queries";
import { formatRupiah } from "@/lib/money";

const statusLabel: Record<string, string> = {
  paid: "Lunas",
  partial: "Sebagian",
  credit: "Kredit",
  void: "Void",
  draft: "Draft",
  needs_review: "Perlu review",
};

function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("id-ID", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export default async function SalesPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { status } = await searchParams;
  const data = await getRecentSales();

  if (!data) {
    redirect("/onboarding");
  }

  const onlyReview = status === "needs_review";
  const reviewCount = data.rows.filter(
    (row) => row.status === "needs_review"
  ).length;
  const rows = onlyReview
    ? data.rows.filter((row) => row.status === "needs_review")
    : data.rows;

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Penjualan</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot;{" "}
          {onlyReview
            ? `${rows.length} transaksi perlu review.`
            : `${rows.length} transaksi terakhir.`}{" "}
          Buka struk untuk cetak ulang.
        </p>
      </div>

      {reviewCount > 0 ? (
        <div className="rounded-lg border border-amber-600/40 bg-amber-50 p-4 text-sm text-amber-900">
          <p className="font-semibold">
            {reviewCount} transaksi perlu review
          </p>
          <p className="mt-1">
            Transaksi dari perangkat offline tidak bisa diproses otomatis karena
            stok atau harga berubah. Tidak ada yang dibuang: setujui untuk
            memotong stok, atau batalkan.
          </p>
          <Link
            href={onlyReview ? "/penjualan" : "/penjualan?status=needs_review"}
            className="mt-2 inline-flex h-11 items-center rounded-md border border-amber-700/40 px-3 font-medium underline-offset-4 hover:bg-amber-100"
          >
            {onlyReview
              ? "Lihat semua transaksi"
              : "Lihat transaksi perlu review"}
          </Link>
        </div>
      ) : null}

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Invoice</th>
              <th className="p-3 font-medium">Waktu</th>
              <th className="p-3 font-medium">Outlet</th>
              <th className="p-3 font-medium">Pelanggan</th>
              <th className="p-3 font-medium">Total</th>
              <th className="p-3 font-medium">Status</th>
              <th className="p-3 font-medium">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr>
                <td
                  colSpan={7}
                  className="text-muted-foreground p-3 text-center"
                >
                  {onlyReview
                    ? "Tidak ada transaksi yang perlu review."
                    : "Belum ada penjualan."}
                </td>
              </tr>
            ) : (
              rows.map((row) => (
                <tr key={row.id} className="border-b last:border-0">
                  <td className="p-3 font-medium whitespace-nowrap">
                    <span className="block">{row.invoiceNo}</span>
                    {row.localInvoiceNo ? (
                      <span className="text-muted-foreground block text-xs font-normal">
                        offline {row.localInvoiceNo}
                      </span>
                    ) : null}
                  </td>
                  <td className="p-3 whitespace-nowrap">
                    {formatDateTime(row.soldAt)}
                  </td>
                  <td className="p-3">{row.outletName}</td>
                  <td className="p-3">{row.customerName ?? "-"}</td>
                  <td className="p-3 whitespace-nowrap">
                    {formatRupiah(row.total)}
                  </td>
                  <td className="p-3">
                    <span
                      className={
                        row.status === "needs_review"
                          ? "font-bold text-amber-700"
                          : undefined
                      }
                    >
                      {statusLabel[row.status] ?? row.status}
                    </span>
                    {row.needsReviewReason ? (
                      <span className="text-muted-foreground block text-xs">
                        {row.needsReviewReason}
                      </span>
                    ) : null}
                  </td>
                  <td className="p-3">
                    <div className="flex gap-3">
                      <Link
                        href={`/penjualan/${row.id}`}
                        className="underline-offset-4 hover:underline"
                      >
                        Detail
                      </Link>
                      <Link
                        href={`/struk/${row.id}`}
                        className="underline-offset-4 hover:underline"
                      >
                        Struk
                      </Link>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
