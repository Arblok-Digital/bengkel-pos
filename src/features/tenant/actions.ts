"use server";

import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import { onboardingSchema } from "./schema";

export type OnboardingState = { error: string | null };

export async function createTenantAction(
  _prev: OnboardingState,
  formData: FormData
): Promise<OnboardingState> {
  const parsed = onboardingSchema.safeParse({
    clientUuid: formData.get("clientUuid"),
    name: formData.get("name"),
    businessType: formData.get("businessType"),
    outletName: formData.get("outletName"),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Isian belum lengkap." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_tenant", {
    p_client_uuid: parsed.data.clientUuid,
    p_name: parsed.data.name,
    p_business_type: parsed.data.businessType,
    p_outlet_name: parsed.data.outletName,
  });

  if (error) {
    if (error.message.includes("client_uuid sudah dipakai")) {
      return { error: "Permintaan ini sudah diproses. Muat ulang halaman." };
    }
    if (error.message.includes("wajib") || error.message.includes("tidak valid")) {
      return { error: error.message };
    }
    return { error: "Gagal membuat usaha. Coba lagi." };
  }

  redirect("/");
}
