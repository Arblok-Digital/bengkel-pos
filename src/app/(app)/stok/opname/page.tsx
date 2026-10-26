import Link from "next/link";
import { redirect } from "next/navigation";

import { getOpnamesPage } from "@/features/inventory/queries";
import { CreateOpnameForm } from "./create-form";

const statusLabel: Record<string, string> = {
  draft: "Draft",
  posted: "Diposting",
  cancelled: "Dibatalkan",
};

function formatDate(value: string): string {
  return new Intl.DateTimeFormat("id-ID", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export default async function OpnamesPage() {
  const data = await getOpnamesPage();

  if (!data) {
    redirect("/onboarding");
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
        <h1 className="mt-2 text-2xl font-bold">Stok Opname</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; hitung fisik lalu posting selisihnya.
        </p>
      </div>

      {data.canWrite ? (
        <CreateOpnameForm tenantId={data.tenantId} outlets={data.outlets} />
      ) : (
        <p className="text-muted-foreground text-sm">
          Hanya pemilik/admin yang dapat membuat opname.
        </p>
      )}

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Waktu</th>
              <th className="p-3 font-medium">Outlet</th>
              <th className="p-3 font-medium">Status</th>
              <th className="p-3 font-medium">Catatan</th>
              <th className="p-3 font-medium">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {data.opnames.length === 0 ? (
              <tr>
                <td colSpan={5} className="text-muted-foreground p-3 text-center">
                  Belum ada opname.
                </td>
              </tr>
            ) : (
              data.opnames.map((row) => (
                <tr key={row.id} className="border-b last:border-0">
                  <td className="p-3 whitespace-nowrap">
                    {formatDate(row.createdAt)}
                  </td>
                  <td className="p-3">{row.outletName}</td>
                  <td className="p-3">
                    <span
                      className={
                        row.status === "posted"
                          ? "font-semibold text-green-700"
                          : ""
                      }
                    >
                      {statusLabel[row.status] ?? row.status}
                    </span>
                  </td>
                  <td className="p-3">{row.note ?? "—"}</td>
                  <td className="p-3">
                    <Link
                      href={`/stok/opname/${row.id}`}
                      className="underline-offset-4 hover:underline"
                    >
                      Buka
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
