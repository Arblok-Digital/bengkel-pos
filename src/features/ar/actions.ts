"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { payReceivableSchema } from "./schema";

export type PayReceivableActionState = {
  error: string | null;
  success: {
    paymentId: string;
    totalPaid: number;
    remaining: number;
    status: string;
  } | null;
};

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

export async function payReceivableAction(
  _prev: PayReceivableActionState,
  formData: FormData
): Promise<PayReceivableActionState> {
  const parsed = payReceivableSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    receivableId: str(formData, "receivableId"),
    amount: str(formData, "amount"),
    method: str(formData, "method"),
    reference: str(formData, "reference"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Data pembayaran tidak valid.",
      success: null,
    };
  }

  const { tenantId, receivableId, amount, method, reference } = parsed.data;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return {
      error: "Sesi tidak valid. Silakan login kembali.",
      success: null,
    };
  }

  const { data, error } = await supabase.rpc("pay_receivable", {
    p_tenant_id: tenantId,
    p_receivable_id: receivableId,
    p_amount: amount,
    p_method: method,
    p_reference: reference || null,
  });

  if (error) {
    return {
      error: error.message || "Gagal mencatat pembayaran piutang.",
      success: null,
    };
  }

  const result = data as {
    payment_id: string;
    total_paid: number;
    remaining: number;
    status: string;
  };

  revalidatePath("/piutang");
  revalidatePath(`/piutang/${receivableId}`);

  return {
    error: null,
    success: {
      paymentId: result.payment_id,
      totalPaid: Number(result.total_paid),
      remaining: Number(result.remaining),
      status: result.status,
    },
  };
}
