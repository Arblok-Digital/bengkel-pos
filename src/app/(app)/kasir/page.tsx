import Link from "next/link";
import { redirect } from "next/navigation";

import { getPosData } from "@/features/pos/queries";
import { PosScreen } from "./pos-screen";

export default async function CashierPage() {
  const data = await getPosData();

  if (!data) {
    redirect("/onboarding");
  }

  if (!data.canSell) {
    return (
      <div className="mx-auto max-w-xl">
        <h1 className="text-2xl font-bold">Kasir</h1>
        <p className="text-muted-foreground mt-2 text-sm">
          Hanya owner, admin, atau kasir yang dapat membuat transaksi penjualan.
        </p>
      </div>
    );
  }

  if (!data.shift) {
    return (
      <div className="mx-auto flex max-w-xl flex-col gap-4">
        <div>
          <h1 className="text-2xl font-bold">Kasir</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            {data.tenantName} &middot; shift belum dibuka.
          </p>
        </div>
        <div className="rounded-lg border bg-card p-4">
          <p className="text-sm">
            Buka shift dulu dan masukkan modal awal sebelum bertransaksi.
          </p>
          <Link
            href="/kasir/shift"
            className="mt-3 inline-flex h-11 items-center rounded-md bg-primary px-4 text-sm font-medium text-primary-foreground"
          >
            Buka kasir / atur shift
          </Link>
        </div>
      </div>
    );
  }

  return <PosScreen data={data} />;
}
