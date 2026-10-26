import { notFound } from "next/navigation";

import { getReceipt } from "@/features/sales/queries";
import { ReceiptView } from "./receipt-view";

export default async function ReceiptPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const data = await getReceipt(id);

  if (!data) {
    notFound();
  }

  return <ReceiptView data={data} />;
}
