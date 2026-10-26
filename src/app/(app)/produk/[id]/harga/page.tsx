import Link from "next/link";
import { redirect } from "next/navigation";

import { getProductPricing } from "@/features/catalog/queries";
import { formatRupiah } from "@/lib/money";
import { PricingManager } from "./pricing-manager";

export default async function ProductPricingPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const data = await getProductPricing(id);

  if (!data) {
    redirect("/produk");
  }

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div>
        <Link
          href={`/produk/${data.product.id}`}
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke produk
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Harga &amp; Konversi</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.product.name} &middot; harga dasar{" "}
          {formatRupiah(data.product.sellPrice)} /{" "}
          {data.product.unitName ?? "satuan"}.
        </p>
      </div>

      <PricingManager data={data} />
    </div>
  );
}
