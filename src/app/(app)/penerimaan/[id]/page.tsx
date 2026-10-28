import Link from "next/link";
import { redirect } from "next/navigation";

import { getGoodsReceiptForEdit } from "@/features/purchasing/queries";

export default async function GoodsReceiptDetailPage({
  params,
}: {
  params: { id: string };
}) {
  const data = await getGoodsReceiptForEdit(params.id);

  if (!data) {
    redirect("/penerimaan");
  }

  return (
    <div className="mx-auto max-w-4xl flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <Link
          href="/penerimaan"
          className="text-sm text-muted-foreground hover:underline"
        >
          ← Kembali ke daftar penerimaan
        </Link>
        <h1 className="text-2xl font-bold">GR {data.grNo}</h1>
        <span
          className={`inline-flex items-center gap-1 px-2.5 py-0.5 rounded text-xs font-medium ${
            data.status === "received"
              ? "bg-green-100 text-green-800"
              : data.status === "cancelled"
                ? "bg-slate-100 text-slate-800"
                : "bg-yellow-100 text-yellow-800"
          }`}
        >
          {data.status === "received" ? "Diterima" : "Dibatalkan"}
        </span>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <div className="bg-card p-3 rounded-lg border">
          <p className="text-xs text-muted-foreground">Supplier</p>
          <p className="font-medium">{data.supplierName}</p>
        </div>
        <div className="bg-card p-3 rounded-lg border">
          <p className="text-xs text-muted-foreground">Outlet</p>
          <p className="font-medium">{data.outletName}</p>
        </div>
        <div className="bg-card p-3 rounded-lg border">
          <p className="text-xs text-muted-foreground">Total</p>
          <p className="font-medium text-right">
            Rp {data.total.toLocaleString("id-ID")}
          </p>
        </div>
        <div className="bg-card p-3 rounded-lg border sm:col-span-3">
          <p className="text-xs text-muted-foreground">Tanggal</p>
          <p className="font-medium">
            {new Date(data.createdAt).toLocaleDateString("id-ID", {
              day: "numeric",
              month: "long",
              year: "numeric",
            })}
          </p>
          {data.purchaseOrderId && data.poNo && (
            <>
              <p className="text-xs text-muted-foreground mt-1">PO Referensi</p>
              <p className="font-medium">
                <Link href={`/pembelian/${data.purchaseOrderId}`}>
                  {data.poNo}
                </Link>
              </p>
            </>
          )}
          {data.note && (
            <>
              <p className="text-xs text-muted-foreground mt-1">Catatan</p>
              <p className="text-sm">{data.note}</p>
            </>
          )}
        </div>
      </div>

      <div className="rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Produk</th>
              <th className="p-3 font-medium">Satuan</th>
              <th className="p-3 font-medium text-right">Qty Terima</th>
              <th className="p-3 font-medium text-right">Harga Pokok</th>
              <th className="p-3 font-medium text-right">Total</th>
              <th className="p-3 font-medium">Catatan</th>
            </tr>
          </thead>
          <tbody>
            {data.items.length === 0 ? (
              <tr>
                <td colSpan={6} className="text-muted-foreground p-3 text-center">
                  Tidak ada item.
                </td>
              </tr>
            ) : (
              data.items.map((item) => (
                <tr key={item.id} className="border-b last:border-0">
                  <td className="p-3">{item.productName}</td>
                  <td className="p-3">{item.unitName}</td>
                  <td className="p-3 text-right">{item.qty}</td>
                  <td className="p-3 text-right">
                    Rp {item.unitCost.toLocaleString("id-ID")}
                  </td>
                  <td className="p-3 text-right font-medium">
                    Rp {item.lineTotal.toLocaleString("id-ID")}
                  </td>
                  <td className="p-3 text-muted-foreground text-sm">
                    {item.note ?? "—"}
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
