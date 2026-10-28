import Link from "next/link";
import { redirect } from "next/navigation";

import { getVehiclesPage, getCustomerOptions } from "@/features/vehicles/queries";
import { VehicleForm } from "./vehicle-form";

export default async function VehiclesPage() {
  const data = await getVehiclesPage();

  if (!data) {
    redirect("/onboarding");
  }

  const customers =
    data.businessType !== "toko_bangunan" && data.canWrite
      ? await getCustomerOptions()
      : [];

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Kendaraan</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            {data.tenantName} &middot; {data.vehicles.length} kendaraan.
          </p>
        </div>
        {data.canWrite && data.businessType !== "toko_bangunan" ? (
          <Link
            href="#tambah-kendaraan"
            className="rounded-md border bg-primary px-4 py-2 text-sm text-primary-foreground hover:bg-primary/90 transition"
          >
            Tambah Kendaraan
          </Link>
        ) : null}
      </div>

      {data.businessType === "toko_bangunan" ? (
        <p className="text-muted-foreground text-sm">
          Modul kendaraan hanya tersedia untuk mode Bengkel.
        </p>
      ) : (
        <>
          {data.canWrite ? (
            <VehicleForm tenantId={data.tenantId} customers={customers} />
          ) : (
            <p className="text-muted-foreground text-sm">
              Hanya pemilik/admin yang dapat mengubah kendaraan.
            </p>
          )}

          <div className="overflow-x-auto rounded-lg border bg-card">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left text-muted-foreground">
                  <th className="p-3 font-medium">Nomor Polisi</th>
                  <th className="p-3 font-medium">Pelanggan</th>
                  <th className="p-3 font-medium">Merk / Model</th>
                  <th className="p-3 font-medium text-center">Tahun</th>
                  <th className="p-3 font-medium text-right">Odometer</th>
                  <th className="p-3 font-medium text-center">Status</th>
                  <th className="p-3 font-medium text-center">Aksi</th>
                </tr>
              </thead>
              <tbody>
                {data.vehicles.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="text-muted-foreground p-3 text-center">
                      Belum ada kendaraan.
                    </td>
                  </tr>
                ) : (
                  data.vehicles.map((v) => (
                    <tr key={v.id} className="border-b last:border-0">
                      <td className="p-3 font-mono font-medium">{v.plateNo}</td>
                      <td className="p-3">{v.customerName}</td>
                      <td className="p-3">
                        <div className="font-medium">
                          {v.brand ?? "—"} {v.model ?? ""}
                        </div>
                      </td>
                      <td className="p-3 text-center">{v.year ?? "—"}</td>
                      <td className="p-3 text-right">
                        {v.lastOdometer ?? "—"} km
                      </td>
                      <td className="p-3 text-center">
                        {v.active ? "Aktif" : "Nonaktif"}
                      </td>
                      <td className="p-3 text-center">
                        <Link
                          href={`/kendaraan/${v.id}`}
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
