"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import {
  workOrderItemSchema,
  workOrderSchema,
  workOrderStatusSchema,
} from "./schema";

export type WorkOrderActionState = { error: string | null };

type Context =
  | { ok: true; supabase: Awaited<ReturnType<typeof createClient>> }
  | { ok: false; error: string };

async function getWriterContext(tenantId: string): Promise<Context> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { ok: false, error: "Sesi tidak valid. Login ulang." };

  const { data } = await supabase
    .from("memberships")
    .select("role")
    .eq("tenant_id", tenantId)
    .eq("user_id", user.id)
    .eq("active", true)
    .maybeSingle();

  if (!data || !["owner", "admin", "mekanik"].includes(data.role)) {
    return { ok: false, error: "Anda tidak berhak mengubah work order." };
  }

  return { ok: true, supabase };
}

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

function mapError(code: string | undefined, message?: string): string {
  if (code === "23503") return "Data referensi tidak valid.";
  if (code === "23505") return "Nomor work order sudah terdaftar.";
  if (code === "23514") return "Nilai work order tidak valid.";
  if (code === "42501") return "Tidak berhak mengubah work order.";
  if (code === "P0001" && message) return message;
  if (code === "P0001") return "Validasi work order gagal.";
  return "Gagal menyimpan work order.";
}

export async function createWorkOrderAction(
  _prev: WorkOrderActionState,
  formData: FormData
): Promise<WorkOrderActionState> {
  const parsed = workOrderSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    outletId: str(formData, "outletId"),
    customerId: str(formData, "customerId"),
    vehicleId: str(formData, "vehicleId"),
    odometer: str(formData, "odometer") || undefined,
    complaint: str(formData, "complaint"),
    diagnosis: str(formData, "diagnosis") || undefined,
    mechanicId: str(formData, "mechanicId") || undefined,
    estimateTotal: str(formData, "estimateTotal") || undefined,
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian work order tidak valid.",
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const itemsRaw = formData.getAll("items");
  const items: unknown[] = [];
  for (const raw of itemsRaw) {
    if (typeof raw !== "string" || raw.trim() === "") continue;
    try {
      const parsedItem: unknown = JSON.parse(raw);
      if (Array.isArray(parsedItem)) {
        items.push(...parsedItem);
      } else {
        items.push(parsedItem);
      }
    } catch {
      // Baris item yang tidak bisa dibaca akan ditolak oleh validasi Zod.
    }
  }

  const itemsParsed = workOrderItemSchema.array().safeParse(items);

  if (!itemsParsed.success) {
    return {
      error: itemsParsed.error.issues[0]?.message ?? "Item work order tidak valid.",
    };
  }

  const payload = itemsParsed.data.map((it) => ({
    product_id: it.productId,
    unit_id: it.unitId,
    qty: it.qty,
    unit_price: it.unitPrice,
    note: it.note ?? null,
  }));

  const { error } = await ctx.supabase.rpc("create_work_order", {
    p_tenant_id: parsed.data.tenantId,
    p_outlet_id: parsed.data.outletId,
    p_customer_id: parsed.data.customerId,
    p_vehicle_id: parsed.data.vehicleId,
    p_odometer: parsed.data.odometer ?? null,
    p_complaint: parsed.data.complaint,
    p_diagnosis: parsed.data.diagnosis ?? null,
    p_mechanic_id: parsed.data.mechanicId ?? null,
    p_estimate_total: parsed.data.estimateTotal ?? 0,
    p_items: payload,
  });

  if (error)
    return {
      error: mapError(
        (error as { code?: string })?.code,
        (error as { message?: string })?.message
      ),
    };

  revalidatePath("/bengkel/work-order");
  redirect("/bengkel/work-order");
}

export async function updateWorkOrderStatusAction(
  _prev: WorkOrderActionState,
  formData: FormData
): Promise<WorkOrderActionState> {
  const parsed = workOrderStatusSchema.safeParse({
    woId: str(formData, "woId"),
    status: str(formData, "status"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Status work order tidak valid.",
    };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Sesi tidak valid. Login ulang." };

  const { data: wo } = await supabase
    .from("work_orders")
    .select("tenant_id")
    .eq("id", parsed.data.woId)
    .maybeSingle();

  if (!wo) return { error: "Work order tidak ditemukan." };

  const ctx = await getWriterContext(wo.tenant_id);
  if (!ctx.ok) return { error: ctx.error };

  const { error } = await ctx.supabase.rpc("update_work_order_status", {
    p_wo_id: parsed.data.woId,
    p_status: parsed.data.status,
  });

  if (error) return { error: mapError((error as { code?: string; message?: string })?.code, (error as { message?: string })?.message) };

  revalidatePath("/bengkel/work-order");
  redirect("/bengkel/work-order");
}
