import { notFound } from "next/navigation";

import { getReceivableDetail } from "@/features/ar/queries";
import { KwitansiView } from "./kwitansi-view";

export default async function KwitansiPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ paymentId?: string }>;
}) {
  const { id } = await params;
  const { paymentId } = await searchParams;

  const data = await getReceivableDetail(id);
  if (!data) {
    notFound();
  }

  // Find target payment or latest payment
  let targetPayment = data.payments.find((p) => p.id === paymentId);
  if (!targetPayment && data.payments.length > 0) {
    targetPayment = data.payments[data.payments.length - 1];
  }

  if (!targetPayment) {
    notFound();
  }

  return (
    <KwitansiView
      data={data}
      payment={targetPayment}
    />
  );
}
