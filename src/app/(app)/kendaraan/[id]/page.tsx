import Link from "next/link";
import { notFound } from "next/navigation";

import { getVehicleForEdit } from "@/features/vehicles/queries";
import { deleteVehicleAction } from "@/features/vehicles/actions";
import { Button } from "@/components/ui/button";

export default async function VehicleDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const vehicle = await getVehicleForEdit(id);

  if (!vehicle) {
    notFound();
  }

  return (
    <div className="mx-auto max-w-3xl flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <Link
          href="/kendaraan"
          className="text-sm font-medium text-muted-foreground hover:text-foreground"
        >
          &larr; Kembali ke Daftar Kendaraan
        </Link>
      </div>

      <div className="rounded-lg border bg-card p-6">
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-bold">{vehicle.plateNo}</h1>
          {vehicle.active ? (
            <span className="inline-block rounded-full border px-2.5 py-0.5 text-xs font-semibold bg-emerald-50 text-emerald-700 border-emerald-200">
              Aktif
            </span>
          ) : (
            <span className="inline-block rounded-full border px-2.5 py-0.5 text-xs font-semibold bg-slate-50 text-slate-700 border-slate-200">
              Nonaktif
            </span>
          )}
        </div>
        <p className="mt-1 text-sm text-muted-foreground">
          Pelanggan:{" "}
          <strong className="text-foreground">{vehicle.customerName}</strong>
        </p>

        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Merk</span>
            <p className="mt-1 text-lg font-bold">{vehicle.brand ?? "—"}</p>
          </div>
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Model</span>
            <p className="mt-1 text-lg font-bold">{vehicle.model ?? "—"}</p>
          </div>
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Tahun</span>
            <p className="mt-1 text-lg font-bold">{vehicle.year ?? "—"}</p>
          </div>
          <div className="rounded-md bg-muted/40 p-3 sm:col-span-2">
            <span className="text-xs text-muted-foreground">VIN / Rangka</span>
            <p className="mt-1 text-lg font-bold">{vehicle.vin ?? "—"}</p>
          </div>
          <div className="rounded-md bg-muted/40 p-3">
            <span className="text-xs text-muted-foreground">Odometer Terakhir</span>
            <p className="mt-1 text-lg font-bold">
              {vehicle.lastOdometer ?? "—"} km
            </p>
          </div>
        </div>
      </div>

      <div className="rounded-lg border bg-card p-6">
        <h2 className="text-base font-semibold mb-4">Hapus Kendaraan</h2>
        <p className="text-sm text-muted-foreground mb-4">
          Menghapus kendaraan ini akan menghapus data kendaraan secara permanen.
        </p>
        <form
          action={async (formData: FormData) => {
            await deleteVehicleAction({ error: null }, formData);
          }}
          className="flex gap-3"
        >
          <input type="hidden" name="tenantId" value={vehicle.tenantId} />
          <input type="hidden" name="id" value={vehicle.id} />
          <Button type="submit" variant="destructive" className="h-10">
            Hapus Kendaraan
          </Button>
          <Link
            href="/kendaraan"
            className="h-10 rounded-md border px-4 text-sm font-medium hover:bg-muted"
          >
            Batal
          </Link>
        </form>
      </div>
    </div>
  );
}
