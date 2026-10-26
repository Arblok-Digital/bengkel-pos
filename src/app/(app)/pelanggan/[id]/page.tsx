import Link from "next/link";
import { redirect } from "next/navigation";

import { getCustomerForEdit } from "@/features/customers/queries";
import { CustomerEditForm } from "../customer-form";

export default async function EditCustomerPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const data = await getCustomerForEdit(id);

  if (!data) {
    redirect("/pelanggan");
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <div>
        <Link
          href="/pelanggan"
          className="text-muted-foreground text-sm underline-offset-4 hover:underline"
        >
          &larr; Kembali ke pelanggan
        </Link>
        <h1 className="mt-2 text-2xl font-bold">Ubah Pelanggan</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          {data.customer.name} &middot; {data.tenantName}
        </p>
      </div>

      <CustomerEditForm
        tenantId={data.tenantId}
        tiers={data.tiers}
        customer={data.customer}
      />
    </div>
  );
}
