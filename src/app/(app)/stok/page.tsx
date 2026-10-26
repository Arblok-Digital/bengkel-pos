import Link from "next/link";
import { redirect } from "next/navigation";

import { getStockByOutlet } from "@/features/inventory/queries";

function formatQty(value: number): string {
  return value.toLocaleString("id-ID", { maximumFractionDigits: 3 });
}

export default async function StockPage() {
  const data = await getStockByOutlet();

  if (!data) {
    redirect("/onboarding");
  }

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Stok</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; {data.rows.length} baris stok. Stok hanya
          berubah lewat movement.
        </p>
        {data.canWrite ? (
          <div className="mt-2 flex flex-wrap gap-4 text-sm">
            <Link
              href="/stok/sesuaikan"
              className="underline-offset-4 hover:underline"
            >
              Sesuaikan stok &rarr;
            </Link>
            <Link
              href="/stok/opname"
              className="underline-offset-4 hover:underline"
            >
              Opname stok &rarr;
            </Link>
          </div>
        ) : null}
      </div>

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Produk</th>
              <th className="p-3 font-medium">SKU</th>
              <th className="p-3 font-medium">Outlet</th>
              <th className="p-3 font-medium">Qty</th>
              <th className="p-3 font-medium">Min</th>
              <th className="p-3 font-medium">Status</th>
            </tr>
          </thead>
          <tbody>
            {data.rows.length === 0 ? (
              <tr>
                <td colSpan={6} className="text-muted-foreground p-3 text-center">
                  Belum ada stok. Stok muncul setelah ada movement.
                </td>
              </tr>
            ) : (
              data.rows.map((row) => (
                <tr
                  key={`${row.outletId}-${row.productId}`}
                  className="border-b last:border-0"
                >
                  <td className="p-3 font-medium">
                    <Link
                      href={`/stok/${row.productId}`}
                      className="underline-offset-4 hover:underline"
                    >
                      {row.productName}
                    </Link>
                  </td>
                  <td className="p-3">{row.sku ?? "—"}</td>
                  <td className="p-3">{row.outletName}</td>
                  <td
                    className={`p-3 whitespace-nowrap ${
                      row.isLow ? "font-semibold text-destructive" : ""
                    }`}
                  >
                    {formatQty(row.qtyBase)}
                  </td>
                  <td className="p-3">{formatQty(row.minStock)}</td>
                  <td className="p-3">
                    {row.isLow ? (
                      <span className="font-semibold text-destructive">
                        Menipis
                      </span>
                    ) : (
                      "Aman"
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <p className="text-muted-foreground text-sm">
        Klik nama produk untuk melihat kartu stok (riwayat movement).
      </p>
    </div>
  );
}
