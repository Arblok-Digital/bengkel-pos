import Link from "next/link";
import { redirect } from "next/navigation";

import { getSuppliersPage } from "@/features/suppliers/queries";
import { SupplierCreateForm } from "./supplier-form";

export default async function SuppliersPage() {
  const data = await getSuppliersPage();

  if (!data) {
    redirect("/onboarding");
  }

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Pemasok</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; {data.suppliers.length} pemasok.
        </p>
      </div>

      {data.canWrite ? (
        <SupplierCreateForm tenantId={data.tenantId} />
      ) : (
        <p className="text-muted-foreground text-sm">
          Hanya pemilik/admin yang dapat mengubah pemasok.
        </p>
      )}

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Pemasok</th>
              <th className="p-3 font-medium">No. HP</th>
              <th className="p-3 font-medium">Termin</th>
              <th className="p-3 font-medium">Status</th>
              <th className="p-3 font-medium">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {data.suppliers.length === 0 ? (
              <tr>
                <td colSpan={5} className="text-muted-foreground p-3 text-center">
                  Belum ada pemasok.
                </td>
              </tr>
            ) : (
              data.suppliers.map((supplier) => (
                <tr key={supplier.id} className="border-b last:border-0">
                  <td className="p-3">
                    <div className="font-medium">{supplier.name}</div>
                    {supplier.address ? (
                      <div className="text-muted-foreground text-xs">
                        {supplier.address}
                      </div>
                    ) : null}
                  </td>
                  <td className="p-3">{supplier.phone ?? "—"}</td>
                  <td className="p-3">
                    {supplier.paymentTermsDays > 0
                      ? `${supplier.paymentTermsDays} hari`
                      : "Tunai"}
                  </td>
                  <td className="p-3">
                    {supplier.active ? (
                      "Aktif"
                    ) : (
                      <span className="font-semibold text-destructive">
                        Nonaktif
                      </span>
                    )}
                  </td>
                  <td className="p-3">
                    {data.canWrite ? (
                      <Link
                        href={`/pemasok/${supplier.id}`}
                        className="underline-offset-4 hover:underline"
                      >
                        Ubah
                      </Link>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
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
