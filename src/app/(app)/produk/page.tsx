import Link from "next/link";
import { redirect } from "next/navigation";

import { getProductsPage } from "@/features/catalog/queries";
import { formatRupiah } from "@/lib/money";
import { ProductCreateForm } from "./product-form";

const kindLabel: Record<string, string> = {
  barang: "Barang",
  jasa: "Jasa",
  paket: "Paket",
};

export default async function ProductsPage() {
  const data = await getProductsPage();

  if (!data) {
    redirect("/onboarding");
  }

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Produk</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; {data.products.length} produk.
        </p>
        {data.canWrite ? (
          <Link
            href="/produk/impor"
            className="mt-2 inline-block text-sm underline-offset-4 hover:underline"
          >
            Impor produk dari CSV &rarr;
          </Link>
        ) : null}
      </div>

      {data.canWrite ? (
        <ProductCreateForm
          tenantId={data.tenantId}
          categories={data.categories}
          units={data.units}
        />
      ) : (
        <p className="text-muted-foreground text-sm">
          Hanya pemilik/admin yang dapat mengubah produk.
        </p>
      )}

      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="p-3 font-medium">Produk</th>
              <th className="p-3 font-medium">Kategori</th>
              <th className="p-3 font-medium">Satuan</th>
              <th className="p-3 font-medium">Jenis</th>
              <th className="p-3 font-medium">Harga jual</th>
              <th className="p-3 font-medium">Status</th>
              <th className="p-3 font-medium">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {data.products.length === 0 ? (
              <tr>
                <td
                  colSpan={7}
                  className="text-muted-foreground p-3 text-center"
                >
                  Belum ada produk.
                </td>
              </tr>
            ) : (
              data.products.map((product) => (
                <tr key={product.id} className="border-b last:border-0">
                  <td className="p-3">
                    <div className="font-medium">{product.name}</div>
                    {product.sku || product.barcode ? (
                      <div className="text-muted-foreground text-xs">
                        {product.sku ? `SKU ${product.sku}` : null}
                        {product.sku && product.barcode ? " · " : null}
                        {product.barcode ? `Barcode ${product.barcode}` : null}
                      </div>
                    ) : null}
                  </td>
                  <td className="p-3">{product.categoryName ?? "—"}</td>
                  <td className="p-3">{product.unitName ?? "—"}</td>
                  <td className="p-3">{kindLabel[product.kind] ?? product.kind}</td>
                  <td className="p-3 whitespace-nowrap">
                    {formatRupiah(product.sellPrice)}
                  </td>
                  <td className="p-3">
                    {product.active ? (
                      "Aktif"
                    ) : (
                      <span className="font-semibold text-destructive">
                        Nonaktif
                      </span>
                    )}
                  </td>
                  <td className="p-3">
                    {data.canWrite ? (
                      <span className="flex items-center gap-3">
                        <Link
                          href={`/produk/${product.id}/harga`}
                          className="underline-offset-4 hover:underline"
                        >
                          Harga
                        </Link>
                        <Link
                          href={`/produk/${product.id}`}
                          className="underline-offset-4 hover:underline"
                        >
                          Ubah
                        </Link>
                      </span>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
