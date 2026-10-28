import { redirect } from "next/navigation";

import { getMyTenants } from "@/features/tenant/queries";
import { setWorkspaceAction } from "@/features/tenant/workspace";

export default async function PilihUsahaPage() {
  const tenants = await getMyTenants();
  if (tenants.length === 0) redirect("/onboarding");

  return (
    <div className="mx-auto max-w-xl space-y-4 p-6">
      <h1 className="text-xl font-semibold">Pilih usaha</h1>
      <div className="space-y-3">
        {tenants.map((t) => (
          <form key={t.tenantId} action={setWorkspaceAction} className="rounded border p-4">
            <input type="hidden" name="tenantId" value={t.tenantId} />
            <div className="mb-2 font-medium">{t.tenantName}</div>
            <div className="mb-3 text-sm text-muted-foreground">
              {t.businessType} · {t.role}
            </div>
            {t.businessType === "both" ? (
              <div className="mb-3 flex gap-3 text-sm">
                <label className="flex items-center gap-1">
                  <input type="radio" name="mode" value="bengkel" defaultChecked /> Bengkel
                </label>
                <label className="flex items-center gap-1">
                  <input type="radio" name="mode" value="toko" /> Toko Bangunan
                </label>
              </div>
            ) : (
              <input
                type="hidden"
                name="mode"
                value={t.businessType === "toko_bangunan" ? "toko" : "bengkel"}
              />
            )}
            <button type="submit" className="rounded bg-primary px-3 py-1.5 text-sm text-primary-foreground">
              Masuk
            </button>
          </form>
        ))}
      </div>
    </div>
  );
}