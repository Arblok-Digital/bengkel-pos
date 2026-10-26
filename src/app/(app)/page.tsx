import Link from "next/link";
import { redirect } from "next/navigation";

import { getLowStock } from "@/features/inventory/queries";
import {
  getMyTenants,
  type BusinessType,
} from "@/features/tenant/queries";

const businessLabel: Record<BusinessType, string> = {
  bengkel: "Bengkel",
  toko_bangunan: "Toko Bangunan",
  both: "Bengkel & Toko Bangunan",
};

const roleLabel: Record<string, string> = {
  owner: "Pemilik",
  admin: "Admin",
  kasir: "Kasir",
  mekanik: "Mekanik",
  gudang: "Gudang",
  dev: "Operator",
};

export default async function DashboardPage() {
  const [tenants, lowStock] = await Promise.all([
    getMyTenants(),
    getLowStock(),
  ]);

  if (tenants.length === 0) {
    redirect("/onboarding");
  }

  const lowCount = lowStock?.rows.length ?? 0;

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Beranda</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            Usaha yang Anda kelola.
          </p>
        </div>
      </div>

      {lowStock && lowCount > 0 ? (
        <Link
          href="/stok/menipis"
          className="flex min-h-11 items-center justify-between gap-3 rounded-lg border border-destructive/40 bg-destructive/5 px-4 py-3 text-sm hover:bg-destructive/10"
        >
          <span>
            <span className="font-semibold text-destructive">Stok menipis</span>
            <span className="text-muted-foreground">
              {" "}
              &middot; {lowCount} barang di bawah stok minimum
            </span>
          </span>
          <span className="font-semibold text-destructive" aria-hidden>
            &rarr;
          </span>
        </Link>
      ) : null}

      <div className="flex flex-col gap-4">
        {tenants.map((tenant) => (
          <section
            key={tenant.tenantId}
            className="rounded-lg border bg-card p-4"
          >
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <h2 className="text-lg font-semibold">{tenant.tenantName}</h2>
              <span className="text-muted-foreground text-xs">
                {businessLabel[tenant.businessType]} &middot;{" "}
                {roleLabel[tenant.role] ?? tenant.role}
              </span>
            </div>
            <div className="mt-3">
              <p className="text-sm font-medium">Outlet</p>
              {tenant.outlets.length === 0 ? (
                <p className="text-muted-foreground text-sm">Belum ada outlet.</p>
              ) : (
                <ul className="text-muted-foreground mt-1 list-inside list-disc text-sm">
                  {tenant.outlets.map((outlet) => (
                    <li key={outlet.id}>{outlet.name}</li>
                  ))}
                </ul>
              )}
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}
