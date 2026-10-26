import Link from "next/link";
import { redirect } from "next/navigation";

import { getOpnameDetail } from "@/features/inventory/queries";
import { OpnameCountForm } from "./opname-count-form";

function formatQty(value: number): string {
  return value.toLocaleString("id-ID", { maximumFractionDigits: 3 });
}

const statusLabel: Record<string, string> = {
  draft: "Draft",
  posted: "Diposting",
  cancelled: "Dibatalkan",
};

export default async function OpnameDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ posted?: string }>;
}) {
  const { id } = await params;
  const query = await searchParams;
  const data = await getOpnameDetail(id);

  if (!data) {
    redirect("/stok/opname");
  }

  const isDraft = data.status === "draft";

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div>
        <Link
          href="/stok/opname"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke daftar opname
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Opname Stok</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.outletName} &middot; {data.tenantName} &middot;{" "}
          <span
            className={
              data.status === "posted" ? "font-semibold text-green-700" : ""
            }
          >
            {statusLabel[data.status] ?? data.status}
          </span>
        </p>
        {data.note ? (
          <p className="text-muted-foreground mt-1 text-sm">
            Catatan: {data.note}
          </p>
        ) : null}
        {query.posted === "1" ? (
          <p className="mt-2 text-sm text-green-700" role="status">
            Opname berhasil diposting. Stok sudah diperbarui.
          </p>
        ) : null}
      </div>

      {data.items.length === 0 ? (
        <p className="text-muted-foreground text-sm">
          Tidak ada produk yang melacak stok untuk outlet ini.
        </p>
      ) : isDraft && data.canWrite ? (
        <OpnameCountForm
          tenantId={data.tenantId}
          opnameId={data.id}
          items={data.items}
        />
      ) : (
        <div className="overflow-x-auto rounded-lg border bg-card">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="p-3 font-medium">Produk</th>
                <th className="p-3 font-medium">Sistem</th>
                <th className="p-3 font-medium">Hitungan</th>
                <th className="p-3 font-medium">Selisih</th>
              </tr>
            </thead>
            <tbody>
              {data.items.map((item) => (
                <tr key={item.id} className="border-b last:border-0">
                  <td className="p-3">{item.productName}</td>
                  <td className="p-3">{formatQty(item.systemQty)}</td>
                  <td className="p-3">
                    {item.countedQty === null
                      ? "—"
                      : formatQty(item.countedQty)}
                  </td>
                  <td
                    className={`p-3 ${
                      item.difference < 0 ? "font-semibold text-destructive" : ""
                    }`}
                  >
                    {data.status === "posted" && item.difference !== 0
                      ? `${item.difference > 0 ? "+" : ""}${formatQty(item.difference)}`
                      : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
