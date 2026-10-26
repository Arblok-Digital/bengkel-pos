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
};

function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("id-ID", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export default async function SalesPage() {
  const data = await getRecentSales();

  if (!data) {
    redirect("/onboarding");
  }

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Penjualan</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; {data.rows.length} transaksi terakhir.
          Buka struk untuk cetak ulang.
        </p>
      </div>

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
            {data.rows.length === 0 ? (
              <tr>
                <td
                  colSpan={7}
                  className="text-muted-foreground p-3 text-center"
                >
                  Belum ada penjualan.
                </td>
              </tr>
            ) : (
              data.rows.map((row) => (
                <tr key={row.id} className="border-b last:border-0">
                  <td className="p-3 font-medium whitespace-nowrap">
                    {row.invoiceNo}
                  </td>
                  <td className="p-3 whitespace-nowrap">
                    {formatDateTime(row.soldAt)}
                  </td>
                  <td className="p-3">{row.outletName}</td>
                  <td className="p-3">{row.customerName ?? "—"}</td>
                  <td className="p-3 whitespace-nowrap">
                    {formatRupiah(row.total)}
                  </td>
                  <td className="p-3">
                    {statusLabel[row.status] ?? row.status}
                  </td>
                  <td className="p-3">
                    <Link
                      href={`/struk/${row.id}`}
                      className="underline-offset-4 hover:underline"
                    >
                      Struk
                    </Link>
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
