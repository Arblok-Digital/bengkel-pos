import { redirect } from "next/navigation";
import { Building2, Store, Wrench } from "lucide-react";

import { getMyTenants } from "@/features/tenant/queries";
import { setWorkspaceAction } from "@/features/tenant/workspace";

export default async function PilihUsahaPage() {
  const tenants = await getMyTenants();
  if (tenants.length === 0) redirect("/onboarding");

  return (
    <div className="mx-auto max-w-3xl space-y-6 py-4 sm:py-10">
      <div className="max-w-xl space-y-2">
        <p className="text-sm font-medium text-muted-foreground">Ruang kerja</p>
        <h1 className="text-3xl font-bold tracking-tight">Pilih usaha</h1>
        <p className="text-muted-foreground">
          Pilih usaha dan jenis operasional yang ingin Anda kelola sekarang.
        </p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        {tenants.map((t) => (
          <form
            key={t.tenantId}
            action={setWorkspaceAction}
            className="rounded-xl border bg-card p-5 shadow-sm"
          >
            <input type="hidden" name="tenantId" value={t.tenantId} />
            <div className="mb-5 flex items-start gap-3">
              <div className="rounded-lg bg-muted p-2.5" aria-hidden>
                {t.businessType === "toko_bangunan" ? (
                  <Store className="size-5" />
                ) : t.businessType === "bengkel" ? (
                  <Wrench className="size-5" />
                ) : (
                  <Building2 className="size-5" />
                )}
              </div>
              <div>
                <h2 className="font-semibold">{t.tenantName}</h2>
                <p className="mt-1 text-sm text-muted-foreground">
                  Peran Anda: {t.role}
                </p>
              </div>
            </div>
            {t.businessType === "both" ? (
              <fieldset className="mb-5 space-y-2">
                <legend className="mb-2 text-sm font-medium">Masuk sebagai</legend>
                <label className="flex min-h-11 items-center gap-2 rounded-lg border px-3 text-sm has-[:checked]:border-primary has-[:checked]:bg-primary/5">
                  <input type="radio" name="mode" value="bengkel" defaultChecked />
                  Bengkel
                </label>
                <label className="flex min-h-11 items-center gap-2 rounded-lg border px-3 text-sm has-[:checked]:border-primary has-[:checked]:bg-primary/5">
                  <input type="radio" name="mode" value="toko" />
                  Toko Bangunan
                </label>
              </fieldset>
            ) : (
              <>
                <p className="mb-5 text-sm text-muted-foreground">
                  {t.businessType === "toko_bangunan"
                    ? "Mode toko bangunan"
                    : "Mode bengkel"}
                </p>
                <input
                  type="hidden"
                  name="mode"
                  value={t.businessType === "toko_bangunan" ? "toko" : "bengkel"}
                />
              </>
            )}
            <button
              type="submit"
              className="inline-flex min-h-11 w-full items-center justify-center rounded-lg bg-primary px-4 text-sm font-medium text-primary-foreground hover:bg-primary/90"
            >
              Masuk ke usaha ini
            </button>
          </form>
        ))}
      </div>
    </div>
  );
}