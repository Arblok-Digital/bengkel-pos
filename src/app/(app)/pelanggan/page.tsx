import Link from "next/link";
import { redirect } from "next/navigation";

import { getCustomersPage } from "@/features/customers/queries";
import { formatRupiah } from "@/lib/money";
import { CustomerCreateForm } from "./customer-form";

export default async function CustomersPage() {
  const data = await getCustomersPage();

  if (!data) {
    redirect("/onboarding");
  }

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Pelanggan</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; {data.customers.length} pelanggan.
        </p>
      </div>

      {data.canWrite ? (
        <CustomerCreateForm tenantId={data.tenantId} tiers={data.tiers} />
      ) : (
        <p className="text-muted-foreground text-sm">
          Hanya pemilik/admin yang dapat mengubah pelanggan.
        </p>
      )}

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Pelanggan</th>
              <th className="p-3 font-medium">No. HP</th>
              <th className="p-3 font-medium">Tier</th>
              <th className="p-3 font-medium">Limit kredit</th>
              <th className="p-3 font-medium">Status</th>
              <th className="p-3 font-medium">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {data.customers.length === 0 ? (
              <tr>
                <td colSpan={6} className="text-muted-foreground p-3 text-center">
                  Belum ada pelanggan.
                </td>
              </tr>
            ) : (
              data.customers.map((customer) => (
                <tr key={customer.id} className="border-b last:border-0">
                  <td className="p-3">
                    <div className="font-medium">{customer.name}</div>
                    {customer.address ? (
                      <div className="text-muted-foreground text-xs">
                        {customer.address}
                      </div>
                    ) : null}
                  </td>
                  <td className="p-3">{customer.phone ?? "—"}</td>
                  <td className="p-3">{customer.tierName ?? "—"}</td>
                  <td className="p-3 whitespace-nowrap">
                    {formatRupiah(customer.creditLimit)}
                  </td>
                  <td className="p-3">
                    {customer.active ? (
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
                        href={`/pelanggan/${customer.id}`}
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
