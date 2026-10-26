import Link from "next/link";
import { redirect } from "next/navigation";

import { getProductForEdit } from "@/features/catalog/queries";
import { ProductEditForm } from "../product-form";

export default async function EditProductPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const data = await getProductForEdit(id);

  if (!data) {
    redirect("/produk");
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <div>
        <Link
          href="/produk"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke produk
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Ubah Produk</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.product.name} &middot; {data.tenantName}
        </p>
        <Link
          href={`/produk/${data.product.id}/harga`}
          className="mt-2 inline-block text-sm underline-offset-4 hover:underline"
        >
          Atur harga tier &amp; konversi satuan &rarr;
        </Link>
      </div>

      <ProductEditForm
        tenantId={data.tenantId}
        categories={data.categories}
        units={data.units}
        product={data.product}
      />
    </div>
  );
}
