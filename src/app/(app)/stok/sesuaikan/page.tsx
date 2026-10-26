import Link from "next/link";
import { redirect } from "next/navigation";

import { getStockAdjustmentData } from "@/features/inventory/queries";
import { AdjustStockForm } from "./adjust-form";

export default async function AdjustStockPage() {
  const data = await getStockAdjustmentData();

  if (!data) {
    redirect("/onboarding");
  }
  if (!data.canWrite) {
    redirect("/stok");
  }

  const clientUuid = crypto.randomUUID();

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
      <div>
        <Link
          href="/stok"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke stok
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Sesuaikan Stok</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; qty positif menambah, negatif mengurangi.
          Alasan wajib diisi.
        </p>
      </div>

      {data.products.length === 0 || data.outlets.length === 0 ? (
        <p className="text-muted-foreground text-sm">
          Butuh minimal satu produk yang melacak stok dan satu outlet.
        </p>
      ) : (
        <AdjustStockForm
          tenantId={data.tenantId}
          products={data.products}
          outlets={data.outlets}
          clientUuid={clientUuid}
        />
      )}
    </div>
  );
}
