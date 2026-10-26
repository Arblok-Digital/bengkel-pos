import { redirect } from "next/navigation";

import { getCatalog } from "@/features/catalog/queries";
import { CatalogManager } from "./catalog-manager";

export default async function CatalogPage() {
  const data = await getCatalog();

  if (!data) {
    redirect("/onboarding");
  }

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Katalog</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; kategori dan satuan dasar.
        </p>
      </div>

      <CatalogManager data={data} />
    </div>
  );
}
