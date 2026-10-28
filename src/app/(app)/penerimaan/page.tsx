import Link from "next/link";
import { redirect } from "next/navigation";

import {
  getGoodsReceiptsPage,
  getOutletOptions,
  getProductOptions,
  getSupplierOptions,
  getUnitOptions,
  getReceivablePurchaseOrders,
} from "@/features/purchasing/queries";
import { ReceiveGoodsForm } from "./create";

export default async function GoodsReceiptsPage() {
  const data = await getGoodsReceiptsPage();

  if (!data) {
    redirect("/onboarding");
  }

  const [outlets, suppliers, products, units, purchaseOrders] = await Promise.all([
    getOutletOptions(),
    getSupplierOptions(),
    getProductOptions(),
    getUnitOptions(),
    getReceivablePurchaseOrders(),
  ]);

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Penerimaan Barang</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            {data.tenantName} &middot; {data.goodsReceipts.length} penerimaan.
          </p>
        </div>
        {data.canWrite ? (
          <Link
            href="/penerimaan"
            className="rounded-md border bg-primary px-4 py-2 text-sm text-primary-foreground hover:bg-primary/90 transition"
          >
            Terima barang
          </Link>
        ) : null}
      </div>

      {data.canWrite ? (
        <ReceiveGoodsForm
          tenantId={data.tenantId}
          outlets={outlets}
          suppliers={suppliers}
          products={products}
          units={units}
          purchaseOrders={purchaseOrders}
        />
      ) : (
        <p className="text-muted-foreground text-sm">
          Hanya pemilik/admin yang dapat menerima barang.
        </p>
      )}

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">No. GR</th>
              <th className="p-3 font-medium">Supplier</th>
              <th className="p-3 font-medium">Outlet</th>
              <th className="p-3 font-medium">PO</th>
              <th className="p-3 font-medium">Status</th>
              <th className="p-3 font-medium text-right">Total</th>
              <th className="p-3 font-medium">Tanggal</th>
              <th className="p-3 font-medium">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {data.goodsReceipts.length === 0 ? (
              <tr>
                <td colSpan={8} className="text-muted-foreground p-3 text-center">
                  Belum ada penerimaan barang.
                </td>
              </tr>
            ) : (
              data.goodsReceipts.map((gr) => (
                <tr key={gr.id} className="border-b last:border-0">
                  <td className="p-3 font-medium">
                    <Link href={`/penerimaan/${gr.id}`} className="hover:underline">
                      {gr.grNo}
                    </Link>
                  </td>
                  <td className="p-3">{gr.supplierName}</td>
                  <td className="p-3">{gr.outletName}</td>
                  <td className="p-3">{gr.poNo ?? "—"}</td>
                  <td className="p-3">
                    <span
                      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium ${
                        gr.status === "received"
                          ? "bg-green-100 text-green-800"
                          : gr.status === "cancelled"
                            ? "bg-slate-100 text-slate-800"
                            : "bg-yellow-100 text-yellow-800"
                      }`}
                    >
                      {gr.status === "received" ? "Diterima" : "Dibatalkan"}
                    </span>
                  </td>
                  <td className="p-3 text-right font-medium">
                    Rp {gr.total.toLocaleString("id-ID")}
                  </td>
                  <td className="p-3 text-muted-foreground">
                    {new Date(gr.createdAt).toLocaleDateString("id-ID", {
                      day: "numeric",
                      month: "short",
                      year: "numeric",
                    })}
                  </td>
                  <td className="p-3">
                    <Link
                      href={`/penerimaan/${gr.id}`}
                      className="underline-offset-4 hover:underline text-sm"
                    >
                      Detail
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
