import Link from "next/link";
import { redirect } from "next/navigation";

import { getShiftPageData } from "@/features/shifts/queries";
import { formatRupiah } from "@/lib/money";
import { CloseShiftForm } from "./close-shift-form";
import { OpenShiftForm } from "./open-shift-form";

function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("id-ID", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export default async function CashierPage({
  searchParams,
}: {
  searchParams: Promise<{ opened?: string; closed?: string }>;
}) {
  const query = await searchParams;
  const data = await getShiftPageData();

  if (!data) {
    redirect("/onboarding");
  }

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div>
        <Link
          href="/kasir"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke kasir
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Shift Kasir</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; buka shift sebelum bertransaksi, tutup shift
          saat kas dihitung.
        </p>
      </div>

      {query.opened === "1" ? (
        <p className="text-sm font-medium text-green-700" role="status">
          Shift kasir dibuka. Selamat bekerja.
        </p>
      ) : null}
      {query.closed === "1" ? (
        <p className="text-sm font-medium text-green-700" role="status">
          Shift kasir ditutup. Selisih kas tersimpan di riwayat.
        </p>
      ) : null}

      {data.currentShift ? (
        <section className="rounded-lg border bg-card p-4">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="text-lg font-semibold">Shift sedang berjalan</h2>
            <span className="text-xs font-semibold text-green-700">Buka</span>
          </div>
          <dl className="mt-3 grid gap-2 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-muted-foreground">Outlet</dt>
              <dd className="font-medium">{data.currentShift.outletName}</dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Dibuka</dt>
              <dd className="font-medium">
                {formatDateTime(data.currentShift.openedAt)}
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Modal awal</dt>
              <dd className="font-medium">
                {formatRupiah(data.currentShift.openingCash)}
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">
                Kas seharusnya (modal awal + tunai masuk)
              </dt>
              <dd className="font-medium">
                {formatRupiah(
                  data.currentShift.expectedCash ??
                    data.currentShift.openingCash
                )}
              </dd>
            </div>
          </dl>

          <div className="mt-4 border-t pt-4">
            <p className="text-muted-foreground text-sm">
              Hitung uang tunai di laci, lalu masukkan jumlahnya. Selisih
              dihitung server dan disimpan apa adanya.
            </p>
            <CloseShiftForm
              tenantId={data.tenantId}
              shiftId={data.currentShift.id}
              clientUuid={crypto.randomUUID()}
            />
          </div>
        </section>
      ) : data.canOpen ? (
        <section className="rounded-lg border bg-card p-4">
          <h2 className="text-lg font-semibold">Buka kasir</h2>
          <p className="text-muted-foreground mt-1 text-sm">
            Masukkan modal awal (uang tunai di laci) sebelum transaksi pertama.
          </p>
          {data.outlets.length === 0 ? (
            <p className="text-muted-foreground mt-3 text-sm">
              Belum ada outlet. Buat outlet dulu di pengaturan.
            </p>
          ) : (
            <OpenShiftForm
              tenantId={data.tenantId}
              outlets={data.outlets}
              clientUuid={crypto.randomUUID()}
            />
          )}
        </section>
      ) : (
        <p className="text-muted-foreground text-sm">
          Hanya owner, admin, atau kasir yang dapat membuka shift kasir.
        </p>
      )}

      <section>
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="text-lg font-semibold">Riwayat shift</h2>
          <Link
            href="/stok/menipis"
            className="text-sm underline-offset-4 hover:underline"
          >
            Stok menipis &rarr;
          </Link>
        </div>
        <div className="mt-2 overflow-x-auto rounded-lg border bg-card">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="p-3 font-medium">Dibuka</th>
                <th className="p-3 font-medium">Outlet</th>
                <th className="p-3 font-medium">Modal</th>
                <th className="p-3 font-medium">Seharusnya</th>
                <th className="p-3 font-medium">Dihitung</th>
                <th className="p-3 font-medium">Selisih</th>
                <th className="p-3 font-medium">Status</th>
              </tr>
            </thead>
            <tbody>
              {data.shifts.length === 0 ? (
                <tr>
                  <td
                    colSpan={7}
                    className="text-muted-foreground p-3 text-center"
                  >
                    Belum ada shift.
                  </td>
                </tr>
              ) : (
                data.shifts.map((shift) => (
                  <tr key={shift.id} className="border-b last:border-0">
                    <td className="p-3 whitespace-nowrap">
                      {formatDateTime(shift.openedAt)}
                      {shift.isOwn ? (
                        <span className="text-muted-foreground"> (Anda)</span>
                      ) : null}
                    </td>
                    <td className="p-3">{shift.outletName}</td>
                    <td className="p-3 whitespace-nowrap">
                      {formatRupiah(shift.openingCash)}
                    </td>
                    <td className="p-3 whitespace-nowrap">
                      {shift.expectedCash === null
                        ? "—"
                        : formatRupiah(shift.expectedCash)}
                    </td>
                    <td className="p-3 whitespace-nowrap">
                      {shift.closingCashCounted === null
                        ? "—"
                        : formatRupiah(shift.closingCashCounted)}
                    </td>
                    <td
                      className={`p-3 whitespace-nowrap ${
                        shift.difference !== null && shift.difference !== 0
                          ? "font-semibold text-destructive"
                          : "font-medium"
                      }`}
                    >
                      {shift.difference === null
                        ? "—"
                        : formatRupiah(shift.difference)}
                    </td>
                    <td className="p-3">
                      {shift.closedAt === null ? "Buka" : "Tutup"}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        <p className="text-muted-foreground mt-2 text-sm">
          Selisih positif = uang lebih, negatif = uang kurang. Penjualan tunai
          dan kas keluar akan ikut dihitung setelah modul transaksi tersedia.
        </p>
      </section>
    </div>
  );
}
