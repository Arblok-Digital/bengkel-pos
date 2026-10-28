import Link from "next/link";
import { redirect } from "next/navigation";

import { getWorkOrdersPage } from "@/features/workorder/queries";
import { WorkOrderForm } from "./work-order-form";

export default async function WorkOrderPage() {
  const data = await getWorkOrdersPage();

  if (!data) {
    redirect("/onboarding");
  }

  const outletId = data.workOrders[0]?.outletId || "";

  const STATUS_LABEL: Record<string, string> = {
    antri: "Antrian",
    dikerjakan: "Dikerjakan",
    menunggu_part: "Menunggu Part",
    selesai: "Selesai",
    ditagih: "Ditagih",
    dibatalkan: "Dibatalkan",
  };

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Work Order</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            {data.tenantName} &middot; {data.workOrders.length} work order.
          </p>
        </div>
        {data.canWrite && data.businessType !== "toko_bangunan" ? (
          <Link
            href="#tambah-wo"
            className="rounded-md border bg-primary px-4 py-2 text-sm text-primary-foreground hover:bg-primary/90 transition"
          >
            Buat Work Order
          </Link>
        ) : null}
      </div>

      {data.businessType === "toko_bangunan" ? (
        <p className="text-muted-foreground text-sm">
          Modul work order hanya tersedia untuk mode Bengkel.
        </p>
      ) : (
        <>
          {data.canWrite ? (
            <WorkOrderForm tenantId={data.tenantId} outletId={outletId} />
          ) : (
            <p className="text-muted-foreground text-sm">
              Hanya pemilik/admin/mekanik yang dapat membuat work order.
            </p>
          )}

          <div className="overflow-x-auto rounded-lg border bg-card">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left text-muted-foreground">
                  <th className="p-3 font-medium text-center">Antrian</th>
                  <th className="p-3 font-medium">WO No</th>
                  <th className="p-3 font-medium">Pelanggan</th>
                  <th className="p-3 font-medium">Kendaraan</th>
                  <th className="p-3 font-medium text-center">Mekanik</th>
                  <th className="p-3 font-medium text-center">Status</th>
                  <th className="p-3 font-medium text-right">Est. Total</th>
                  <th className="p-3 font-medium text-center">Aksi</th>
                </tr>
              </thead>
              <tbody>
                {data.workOrders.length === 0 ? (
                  <tr>
                    <td colSpan={8} className="text-muted-foreground p-3 text-center">
                      Belum ada work order.
                    </td>
                  </tr>
                ) : (
                  data.workOrders.map((wo) => (
                    <tr key={wo.id} className="border-b last:border-0">
                      <td className="p-3 font-mono font-medium text-center">
                        #{wo.queueNo}
                      </td>
                      <td className="p-3 font-mono font-medium">{wo.woNo}</td>
                      <td className="p-3">{wo.customerName}</td>
                      <td className="p-3">{wo.vehiclePlate}</td>
                      <td className="p-3">{wo.mechanicName}</td>
                      <td className="p-3 text-center">
                        <span
                          className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold ${
                            wo.status === "selesai"
                              ? "bg-emerald-50 text-emerald-700 border-emerald-200"
                              : wo.status === "ditagih"
                              ? "bg-blue-50 text-blue-700 border-blue-200"
                              : wo.status === "dibatalkan"
                              ? "bg-slate-50 text-slate-700 border-slate-200"
                              : wo.status === "dikerjakan"
                              ? "bg-amber-50 text-amber-700 border-amber-200"
                              : wo.status === "menunggu_part"
                              ? "bg-orange-50 text-orange-700 border-orange-200"
                              : "bg-muted text-muted-foreground border-muted"
                          }`}
                        >
                          {STATUS_LABEL[wo.status] ?? wo.status}
                        </span>
                      </td>
                      <td className="p-3 text-right font-mono">
                        Rp {wo.estimateTotal.toLocaleString("id-ID")}
                      </td>
                      <td className="p-3 text-center">
                        <Link
                          href={`/bengkel/work-order/${wo.id}`}
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
        </>
      )}
    </div>
  );
}
