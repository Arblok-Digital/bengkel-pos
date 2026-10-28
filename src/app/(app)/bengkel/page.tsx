import Link from "next/link";
import { CarFront, ClipboardList, ShoppingCart, Wrench } from "lucide-react";

import { getWorkspace } from "@/features/tenant/workspace";

const quickActions = [
  {
    href: "/bengkel/work-order",
    title: "Work Order",
    description: "Buat dan pantau antrean servis kendaraan.",
    icon: ClipboardList,
  },
  {
    href: "/kendaraan",
    title: "Kendaraan",
    description: "Kelola data kendaraan dan pelanggan pemiliknya.",
    icon: CarFront,
  },
  {
    href: "/kasir",
    title: "Kasir",
    description: "Buat transaksi sparepart dan jasa.",
    icon: ShoppingCart,
  },
] as const;

export default async function BengkelDashboardPage() {
  const workspace = await getWorkspace();

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-8">
      <section className="rounded-2xl border bg-card p-6 sm:p-8">
        <div className="flex items-start gap-4">
          <div className="rounded-xl bg-primary p-3 text-primary-foreground" aria-hidden>
            <Wrench className="size-7" />
          </div>
          <div>
            <p className="text-sm font-medium text-muted-foreground">Operasional bengkel</p>
            <h1 className="mt-1 text-3xl font-bold tracking-tight">
              {workspace?.tenantName ?? "Bengkel"}
            </h1>
            <p className="mt-2 max-w-2xl text-muted-foreground">
              Mulai dari work order untuk servis kendaraan, lalu lanjutkan ke kasir saat pekerjaan selesai.
            </p>
          </div>
        </div>
      </section>

      <section>
        <h2 className="text-lg font-semibold">Aksi cepat</h2>
        <div className="mt-3 grid gap-3 sm:grid-cols-3">
          {quickActions.map((action) => {
            const Icon = action.icon;
            return (
              <Link
                key={action.href}
                href={action.href}
                className="group flex min-h-40 flex-col rounded-xl border bg-card p-5 transition-colors hover:border-primary/50 hover:bg-muted/40"
              >
                <Icon className="size-6" aria-hidden />
                <h3 className="mt-5 font-semibold group-hover:text-primary">{action.title}</h3>
                <p className="mt-1 text-sm text-muted-foreground">{action.description}</p>
              </Link>
            );
          })}
        </div>
      </section>

      <section className="rounded-xl border border-dashed bg-card/60 p-5">
        <h2 className="font-semibold">Alur kerja yang disarankan</h2>
        <ol className="mt-3 grid gap-3 text-sm text-muted-foreground sm:grid-cols-3">
          <li><span className="font-semibold text-foreground">1. Catat kendaraan</span><br />Pilih pelanggan dan kendaraan yang datang.</li>
          <li><span className="font-semibold text-foreground">2. Buat work order</span><br />Masukkan keluhan, mekanik, jasa, dan sparepart.</li>
          <li><span className="font-semibold text-foreground">3. Selesaikan di kasir</span><br />Catat pembayaran dan cetak struk.</li>
        </ol>
      </section>
    </div>
  );
}