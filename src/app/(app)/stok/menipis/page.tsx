import Link from "next/link";
import { redirect } from "next/navigation";

import { getLowStock } from "@/features/inventory/queries";

function formatQty(value: number): string {
  return value.toLocaleString("id-ID", { maximumFractionDigits: 3 });
}

export default async function LowStockPage() {
  const data = await getLowStock();

  if (!data) {
    redirect("/onboarding");
  }

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div>
        <Link
          href="/stok"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke stok
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Stok Menipis</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot;{" "}
          {data.rows.length === 0
            ? "semua produk di atas stok minimum."
            : `${data.rows.length} produk di bawah stok minimum.`}
        </p>
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
              <th className="p-3 font-medium">Kurang</th>
            </tr>
          </thead>
          <tbody>
            {data.rows.length === 0 ? (
              <tr>
                <td
                  colSpan={6}
                  className="text-muted-foreground p-3 text-center"
                >
                  Tidak ada stok menipis. Semua aman.
                </td>
              </tr>
            ) : (
              data.rows.map((row) => (
                <tr
                  key={`${row.outletName}-${row.productId}`}
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
                  <td className="p-3 font-semibold whitespace-nowrap text-destructive">
                    {formatQty(row.qtyBase)}
                  </td>
                  <td className="p-3">{formatQty(row.minStock)}</td>
                  <td className="p-3 whitespace-nowrap">
                    {formatQty(row.shortage)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="flex flex-wrap gap-4 text-sm">
        <Link href="/stok" className="underline-offset-4 hover:underline">
          Lihat semua stok &rarr;
        </Link>
        {data.canWrite ? (
          <Link
            href="/stok/sesuaikan"
            className="underline-offset-4 hover:underline"
          >
            Sesuaikan stok &rarr;
          </Link>
        ) : null}
      </div>

      <p className="text-muted-foreground text-sm">
        Stok dianggap menipis bila produk melacak stok dan qty berada di bawah
        stok minimum yang diisi di data produk.
      </p>
    </div>
  );
}
