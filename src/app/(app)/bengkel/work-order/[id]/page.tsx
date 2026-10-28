import Link from "next/link";
import { notFound } from "next/navigation";

import { getWorkOrderDetail } from "@/features/workorder/queries";
import { formatRupiah } from "@/lib/money";
import { WorkOrderSaleForm } from "./work-order-sale-form";
import { WorkOrderStatusForm } from "./work-order-status-form";

const STATUS_LABEL: Record<string, string> = {
  antri: "Antrian",
  dikerjakan: "Dikerjakan",
  menunggu_part: "Menunggu Part",
  selesai: "Selesai",
  ditagih: "Ditagih",
  dibatalkan: "Dibatalkan",
};

const STATUS_BADGE: Record<string, string> = {
  selesai: "bg-emerald-50 text-emerald-700 border-emerald-200",
  ditagih: "bg-blue-50 text-blue-700 border-blue-200",
  dibatalkan: "bg-slate-50 text-slate-700 border-slate-200",
  dikerjakan: "bg-amber-50 text-amber-700 border-amber-200",
  menunggu_part: "bg-orange-50 text-orange-700 border-orange-200",
  antri: "bg-muted text-muted-foreground border-muted",
};

export default async function WorkOrderDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const detail = await getWorkOrderDetail(id);

  if (!detail) {
    notFound();
  }

  const { workOrder, items } = detail;

  // Status 'ditagih' hanya didapat lewat konversi penjualan, jadi tombol ubah
  // status hanya muncul untuk WO yang masih punya langkah berikutnya.
  const canTransition = ["antri", "dikerjakan", "menunggu_part"].includes(
    workOrder.status
  );

  return (
    <div className="mx-auto max-w-4xl flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <Link
          href="/bengkel/work-order"
          className="text-sm font-medium text-muted-foreground hover:text-foreground"
        >
          &larr; Kembali ke Daftar Work Order
        </Link>
      </div>

      <div className="rounded-lg border bg-card p-6">
        <div className="flex items-center gap-3 mb-4">
          <h1 className="text-2xl font-bold">{workOrder.woNo}</h1>
          <span
            className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold ${
              STATUS_BADGE[workOrder.status]
            }`}
          >
            {STATUS_LABEL[workOrder.status]}
          </span>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 mb-6">
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Antrian</span>
            <p className="mt-1 text-lg font-bold font-mono">
              #{workOrder.queueNo}
            </p>
          </div>
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Pelanggan</span>
            <p className="mt-1 text-lg font-bold">{workOrder.customerName}</p>
          </div>
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Kendaraan</span>
            <p className="mt-1 text-lg font-bold">{workOrder.vehiclePlate}</p>
          </div>
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Mekanik</span>
            <p className="mt-1 text-lg font-bold">{workOrder.mechanicName}</p>
          </div>
        </div>
        <div className="rounded-md bg-muted/40 p-4">
          <span className="text-xs text-muted-foreground block mb-1">Keluhan</span>
          <p className="text-sm">{workOrder.complaint}</p>
          {workOrder.diagnosis && (
            <>
              <span className="text-xs text-muted-foreground block mt-2 mb-1">
                Diagnosis
              </span>
              <p className="text-sm">{workOrder.diagnosis}</p>
            </>
          )}
          <span className="text-xs text-muted-foreground block mt-3 mb-1">
            Odometer
          </span>
          <p className="text-sm">
            {workOrder.odometer ?? "—"} km
          </p>
          <span className="text-xs text-muted-foreground block mt-3 mb-1">
            Estimasi Total
          </span>
          <p className="text-sm font-mono font-medium">
            {formatRupiah(workOrder.estimateTotal)}
          </p>
        </div>
      </div>

      <div className="rounded-lg border bg-card p-6">
        <h2 className="text-lg font-semibold mb-4">Item (Jasa / Sparepart)</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="p-3 font-medium">Produk</th>
                <th className="p-3 font-medium text-right">Qty</th>
                <th className="p-3 font-medium text-right">Harga Satuan</th>
                <th className="p-3 font-medium text-right">Total</th>
                <th className="p-3 font-medium">Catatan</th>
              </tr>
            </thead>
            <tbody>
              {items.length === 0 ? (
                <tr>
                  <td colSpan={5} className="text-muted-foreground p-3 text-center">
                    Belum ada item.
                  </td>
                </tr>
              ) : (
                items.map((it) => (
                  <tr key={it.id} className="border-b last:border-0">
                    <td className="p-3">{it.productName}</td>
                    <td className="p-3 text-right">{it.qty}</td>
                    <td className="p-3 text-right font-mono">
                      {formatRupiah(it.unitPrice)}
                    </td>
                    <td className="p-3 text-right font-mono font-medium">
                      {formatRupiah(it.lineTotal)}
                    </td>
                    <td className="p-3">{it.note ?? "—"}</td>
                  </tr>
                ))
              )}
              <tr className="border-t font-bold">
                <td colSpan={3} className="p-3 text-right">
                  Total Item:
                </td>
                <td className="p-3 text-right font-mono">
                  {formatRupiah(items.reduce((s, it) => s + it.lineTotal, 0))}
                </td>
                <td className="p-3"></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      {workOrder.saleId ? (
        <section className="rounded-lg border border-blue-200 bg-blue-50 p-5">
          <h2 className="text-lg font-semibold text-blue-950">Work order sudah ditagihkan</h2>
          <p className="mt-1 text-sm text-blue-900">
            Penjualan untuk work order ini sudah dibuat. Perubahan stok dan pembayaran tercatat pada nota tersebut.
          </p>
          <Link
            href={`/penjualan/${workOrder.saleId}`}
            className="mt-3 inline-flex min-h-11 items-center rounded-md bg-blue-700 px-4 text-sm font-medium text-white hover:bg-blue-800"
          >
            Buka nota penjualan
          </Link>
        </section>
      ) : workOrder.status === "selesai" && items.length > 0 ? (
        <WorkOrderSaleForm
          workOrderId={workOrder.id}
          estimatedTotal={items.reduce((sum, item) => sum + item.lineTotal, 0)}
        />
      ) : null}

      {canTransition && (
        <div className="rounded-lg border bg-card p-6">
          <h2 className="text-lg font-semibold mb-4">Ubah Status</h2>
          <p className="text-sm text-muted-foreground mb-4">
            Pilih status berikutnya untuk work order ini.
          </p>
          <WorkOrderStatusForm woId={workOrder.id} status={workOrder.status} />
        </div>
      )}
    </div>
  );
}
