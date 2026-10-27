import Link from "next/link";
import { redirect } from "next/navigation";

import { getSaleDetail } from "@/features/sales/queries";
import { formatRupiah } from "@/lib/money";
import { SaleActions } from "./sale-actions";

const statusLabel: Record<string, string> = {
  paid: "Lunas",
  partial: "Sebagian",
  credit: "Kredit",
  void: "Void",
  draft: "Draft",
};

function formatQty(value: number): string {
  return value.toLocaleString("id-ID", { maximumFractionDigits: 3 });
}

function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("id-ID", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export default async function SaleDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const detail = await getSaleDetail(id);

  if (!detail) {
    redirect("/penjualan");
  }

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div>
        <Link
          href="/penjualan"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke penjualan
        </Link>
        <div className="mt-2 flex flex-wrap items-baseline justify-between gap-2">
          <h1 className="text-2xl font-bold">{detail.invoiceNo}</h1>
          <span
            className={
              detail.status === "void"
                ? "font-semibold text-destructive"
                : "font-semibold text-green-700"
            }
          >
            {statusLabel[detail.status] ?? detail.status}
          </span>
        </div>
        <p className="text-muted-foreground mt-1 text-sm">
          {formatDateTime(detail.soldAt)} &middot; {detail.outletName}
          {detail.customerName ? ` · ${detail.customerName}` : ""}
        </p>
        {detail.voidReason ? (
          <p className="mt-2 text-sm text-destructive">
            Alasan void: {detail.voidReason}
          </p>
        ) : null}
      </div>

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Produk</th>
              <th className="p-3 font-medium">Qty</th>
              <th className="p-3 font-medium">Harga</th>
              <th className="p-3 font-medium">Total</th>
              <th className="p-3 font-medium">Diretur</th>
            </tr>
          </thead>
          <tbody>
            {detail.items.map((item) => (
              <tr key={item.id} className="border-b last:border-0">
                <td className="p-3">{item.name}</td>
                <td className="p-3 whitespace-nowrap">
                  {formatQty(item.qty)} {item.unitName}
                </td>
                <td className="p-3 whitespace-nowrap">
                  {formatRupiah(item.unitPrice)}
                </td>
                <td className="p-3 whitespace-nowrap">
                  {formatRupiah(item.lineTotal)}
                </td>
                <td className="p-3 whitespace-nowrap">
                  {item.returnedQty > 0
                    ? `${formatQty(item.returnedQty)} ${item.unitName}`
                    : "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 text-sm">
        <Link
          href={`/struk/${detail.id}`}
          className="inline-flex h-11 items-center rounded-md border border-input px-4 hover:bg-accent"
        >
          Lihat / cetak struk
        </Link>
        <p>
          Total <strong>{formatRupiah(detail.invoiceTotal)}</strong> &middot;
          dibayar {formatRupiah(detail.paidAmount)}
        </p>
      </div>

      {detail.returns.length > 0 ? (
        <section>
          <h2 className="text-lg font-semibold">Riwayat retur</h2>
          <ul className="mt-2 flex flex-col gap-2">
            {detail.returns.map((row) => (
              <li key={row.id} className="rounded-lg border bg-card p-3 text-sm">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <span className="font-medium">
                    {formatDateTime(row.createdAt)}
                  </span>
                  <span className="font-semibold">
                    {formatRupiah(row.total)}
                  </span>
                </div>
                <p className="text-muted-foreground mt-1">
                  {row.items
                    .map(
                      (item) =>
                        `${item.name} ${formatQty(item.qty)} ${item.unitName}`
                    )
                    .join(", ")}
                </p>
                <p className="mt-1">Alasan: {row.reason}</p>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {detail.canManage ? <SaleActions detail={detail} /> : null}

      <p className="text-muted-foreground text-sm">
        Void & retur hanya untuk pemilik/admin dan wajib beralasan. Stok
        dikembalikan lewat movement, dokumen asli tidak diedit.
      </p>
    </div>
  );
}
