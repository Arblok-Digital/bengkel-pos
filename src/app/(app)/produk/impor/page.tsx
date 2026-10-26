import Link from "next/link";
import { redirect } from "next/navigation";

import { getCatalog } from "@/features/catalog/queries";
import { ImportCsvForm } from "./import-form";

export default async function ImportProductsPage() {
  const data = await getCatalog();

  if (!data) {
    redirect("/onboarding");
  }
  if (!data.canWrite) {
    redirect("/produk");
  }

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div>
        <Link
          href="/produk"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke produk
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Impor Produk (CSV)</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.tenantName} &middot; pratinjau dulu, baru impor.
        </p>
      </div>

      <section className="rounded-lg border bg-card p-4 text-sm">
        <h2 className="font-semibold">Format CSV</h2>
        <p className="text-muted-foreground mt-1">
          Header wajib:{" "}
          <code>
            nama,sku,barcode,kategori,satuan,harga_jual,stok_minimum,jenis
          </code>
          . Kolom kategori/sku/barcode boleh kosong. Jenis: barang, jasa, paket.
        </p>
        <pre className="mt-2 overflow-x-auto rounded-md bg-muted p-2 text-xs">
{`nama,sku,barcode,kategori,satuan,harga_jual,stok_minimum,jenis
Oli Mesin 1L,OLI-1L,8990001,Oli,liter,50000,2,barang
Jasa Servis,JASA-1,,,jam,75000,0,jasa`}
        </pre>
        <p className="text-muted-foreground mt-2">
          Satuan &amp; kategori harus sudah ada di Katalog. Maksimal 1000 baris.
        </p>
      </section>

      <ImportCsvForm tenantId={data.tenantId} />
    </div>
  );
}
