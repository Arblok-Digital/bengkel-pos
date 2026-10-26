import Link from "next/link";
import { redirect } from "next/navigation";

import { getStockCard } from "@/features/inventory/queries";

const typeLabel: Record<string, string> = {
  purchase: "Pembelian",
  sale: "Penjualan",
  sale_return: "Retur jual",
  adjustment: "Penyesuaian",
  opname: "Opname",
  transfer_in: "Transfer masuk",
  transfer_out: "Transfer keluar",
  workorder_use: "Pakai WO",
};

function formatQty(value: number): string {
  return value.toLocaleString("id-ID", { maximumFractionDigits: 3 });
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat("id-ID", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export default async function StockCardPage({
  params,
}: {
  params: Promise<{ productId: string }>;
}) {
  const { productId } = await params;
  const data = await getStockCard(productId);

  if (!data) {
    redirect("/stok");
  }

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div>
        <Link
          href="/stok"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke stok
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Kartu Stok</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.productName}
          {data.sku ? ` · ${data.sku}` : ""} &middot; min{" "}
          {formatQty(data.minStock)} &middot; {data.tenantName}
        </p>
      </div>

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Waktu</th>
              <th className="p-3 font-medium">Outlet</th>
              <th className="p-3 font-medium">Tipe</th>
              <th className="p-3 font-medium">Qty</th>
              <th className="p-3 font-medium">Catatan</th>
            </tr>
          </thead>
          <tbody>
            {data.rows.length === 0 ? (
              <tr>
                <td colSpan={5} className="text-muted-foreground p-3 text-center">
                  Belum ada movement untuk produk ini.
                </td>
              </tr>
            ) : (
              data.rows.map((row) => (
                <tr key={row.id} className="border-b last:border-0">
                  <td className="p-3 whitespace-nowrap">
                    {formatDate(row.createdAt)}
                  </td>
                  <td className="p-3">{row.outletName}</td>
                  <td className="p-3">{typeLabel[row.type] ?? row.type}</td>
                  <td
                    className={`p-3 whitespace-nowrap font-medium ${
                      row.qtyBase < 0 ? "text-destructive" : "text-green-700"
                    }`}
                  >
                    {row.qtyBase > 0 ? "+" : ""}
                    {formatQty(row.qtyBase)}
                  </td>
                  <td className="p-3">{row.note ?? "—"}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
