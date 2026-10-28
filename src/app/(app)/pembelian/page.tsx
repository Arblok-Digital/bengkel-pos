import Link from "next/link";
import { redirect } from "next/navigation";

import { getPurchaseOrdersPage } from "@/features/purchasing/queries";
import {
  getOutletOptions,
  getProductOptions,
  getSupplierOptions,
  getUnitOptions,
} from "@/features/purchasing/queries";
import { CreatePurchaseOrderForm } from "./create";

export default async function PurchaseOrdersPage() {
  const data = await getPurchaseOrdersPage();

  if (!data) {
    redirect("/onboarding");
  }

  const [outlets, suppliers, products, units] = await Promise.all([
    getOutletOptions(),
    getSupplierOptions(),
    getProductOptions(),
    getUnitOptions(),
  ]);

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Pembelian</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            {data.tenantName} &middot; {data.purchaseOrders.length} PO.
          </p>
        </div>
        {data.canWrite ? (
          <Link href="/pembelian/buat" className="rounded-md border bg-primary px-4 py-2 text-sm text-primary-foreground hover:bg-primary/90 transition">
            Buat PO
          </Link>
        ) : null}
      </div>

      {data.canWrite ? (
        <CreatePurchaseOrderForm
          tenantId={data.tenantId}
          outlets={outlets}
          suppliers={suppliers}
          products={products}
          units={units}
        />
      ) : (
        <p className="text-muted-foreground text-sm">
          Hanya pemilik/admin yang dapat membuat PO.
        </p>
      )}

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">No. PO</th>
              <th className="p-3 font-medium">Supplier</th>
              <th className="p-3 font-medium">Outlet</th>
              <th className="p-3 font-medium">Status</th>
              <th className="p-3 font-medium text-right">Total</th>
              <th className="p-3 font-medium">Tanggal</th>
              <th className="p-3 font-medium">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {data.purchaseOrders.length === 0 ? (
              <tr>
                <td colSpan={7} className="text-muted-foreground p-3 text-center">
                  Belum ada PO.
                </td>
              </tr>
            ) : (
              data.purchaseOrders.map((po) => (
                <tr key={po.id} className="border-b last:border-0">
                  <td className="p-3 font-medium">
                    <Link href={`/pembelian/${po.id}`} className="hover:underline">
                      {po.poNo}
                    </Link>
                  </td>
                  <td className="p-3">{po.supplierName}</td>
                  <td className="p-3">{po.outletName}</td>
                  <td className="p-3">
                    <span
                      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium ${
                        po.status === "draft"
                          ? "bg-yellow-100 text-yellow-800"
                          : po.status === "ordered"
                            ? "bg-blue-100 text-blue-800"
                            : po.status === "partial"
                              ? "bg-orange-100 text-orange-800"
                              : po.status === "received"
                                ? "bg-green-100 text-green-800"
                                : "bg-slate-100 text-slate-800"
                      }`}
                    >
                      {po.status === "draft"
                        ? "Draft"
                        : po.status === "ordered"
                          ? "Dipesan"
                          : po.status === "partial"
                            ? "Parsial"
                            : po.status === "received"
                              ? "Diterima"
                              : "Dibatalkan"}
                    </span>
                  </td>
                  <td className="p-3 text-right font-medium">
                    Rp {po.total.toLocaleString("id-ID")}
                  </td>
                  <td className="p-3 text-muted-foreground">
                    {new Date(po.createdAt).toLocaleDateString("id-ID", {
                      day: "numeric",
                      month: "short",
                      year: "numeric",
                    })}
                  </td>
                  <td className="p-3">
                    <Link
                      href={`/pembelian/${po.id}`}
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
