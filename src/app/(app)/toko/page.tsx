import Link from "next/link";
import { Boxes, PackageSearch, ShoppingCart, Store } from "lucide-react";

import { getWorkspace } from "@/features/tenant/workspace";

const quickActions = [
  {
    href: "/kasir",
    title: "Kasir",
    description: "Buat transaksi penjualan dan pilih metode pembayaran.",
    icon: ShoppingCart,
  },
  {
    href: "/produk",
    title: "Produk & Harga",
    description: "Atur barang, jasa, satuan, harga, dan tier pelanggan.",
    icon: PackageSearch,
  },
  {
    href: "/stok",
    title: "Stok",
    description: "Pantau stok, stok menipis, opname, dan penyesuaian.",
    icon: Boxes,
  },
] as const;

export default async function TokoDashboardPage() {
  const workspace = await getWorkspace();

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-8">
      <section className="rounded-2xl border bg-card p-6 sm:p-8">
        <div className="flex items-start gap-4">
          <div className="rounded-xl bg-primary p-3 text-primary-foreground" aria-hidden>
            <Store className="size-7" />
          </div>
          <div>
            <p className="text-sm font-medium text-muted-foreground">Operasional toko bangunan</p>
            <h1 className="mt-1 text-3xl font-bold tracking-tight">
              {workspace?.tenantName ?? "Toko Bangunan"}
            </h1>
            <p className="mt-2 max-w-2xl text-muted-foreground">
              Kelola katalog, stok, pembelian, dan transaksi penjualan dari satu ruang kerja toko.
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
          <li><span className="font-semibold text-foreground">1. Siapkan produk</span><br />Atur satuan, harga jual, dan stok minimum.</li>
          <li><span className="font-semibold text-foreground">2. Pantau persediaan</span><br />Catat pembelian dan penerimaan barang.</li>
          <li><span className="font-semibold text-foreground">3. Layani penjualan</span><br />Gunakan kasir untuk transaksi tunai atau tempo.</li>
        </ol>
      </section>
    </div>
  );
}