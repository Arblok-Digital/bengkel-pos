import Link from "next/link";
import { redirect } from "next/navigation";

import { getSupplierForEdit } from "@/features/suppliers/queries";
import { SupplierEditForm } from "../supplier-form";

export default async function EditSupplierPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const data = await getSupplierForEdit(id);

  if (!data) {
    redirect("/pemasok");
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <div>
        <Link
          href="/pemasok"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke pemasok
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Ubah Pemasok</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.supplier.name} &middot; {data.tenantName}
        </p>
      </div>

      <SupplierEditForm tenantId={data.tenantId} supplier={data.supplier} />
    </div>
  );
}
