"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import {
  deleteVehicleSchema,
  updateVehicleSchema,
  vehicleSchema,
} from "./schema";

export type VehicleActionState = { error: string | null };

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

  if (!data || !["owner", "admin"].includes(data.role)) {
    return { ok: false, error: "Anda tidak berhak mengubah kendaraan." };
  }

  return { ok: true, supabase };
}

function str(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

function mapError(code: string | undefined): string {
  if (code === "23503") return "Pelanggan tidak valid.";
  if (code === "23505") return "Nomor polisi sudah terdaftar.";
  if (code === "23514") return "Nilai kendaraan tidak valid.";
  if (code === "42501") return "Tidak berhak mengubah kendaraan.";
  return "Gagal menyimpan kendaraan.";
}

export async function createVehicleAction(
  _prev: VehicleActionState,
  formData: FormData
): Promise<VehicleActionState> {
  const parsed = vehicleSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    customerId: str(formData, "customerId"),
    plateNo: str(formData, "plateNo"),
    brand: str(formData, "brand"),
    model: str(formData, "model"),
    year: str(formData, "year") || undefined,
    vin: str(formData, "vin") || undefined,
    lastOdometer: str(formData, "lastOdometer") || undefined,
    active: formData.get("active") === "on",
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian kendaraan tidak valid.",
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { error } = await ctx.supabase.from("vehicles").insert({
    tenant_id: parsed.data.tenantId,
    customer_id: parsed.data.customerId,
    plate_no: parsed.data.plateNo,
    brand: parsed.data.brand || null,
    model: parsed.data.model || null,
    year: parsed.data.year,
    vin: parsed.data.vin,
    last_odometer: parsed.data.lastOdometer,
    active: parsed.data.active,
  });

  if (error) return { error: mapError(error.code) };

  revalidatePath("/kendaraan");
  redirect("/kendaraan");
}

export async function updateVehicleAction(
  _prev: VehicleActionState,
  formData: FormData
): Promise<VehicleActionState> {
  const parsed = updateVehicleSchema.safeParse({
    id: str(formData, "id"),
    tenantId: str(formData, "tenantId"),
    customerId: str(formData, "customerId"),
    plateNo: str(formData, "plateNo"),
    brand: str(formData, "brand"),
    model: str(formData, "model"),
    year: str(formData, "year") || undefined,
    vin: str(formData, "vin") || undefined,
    lastOdometer: str(formData, "lastOdometer") || undefined,
    active: formData.get("active") === "on",
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian kendaraan tidak valid.",
    };
  }

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { data, error } = await ctx.supabase
    .from("vehicles")
    .update({
      customer_id: parsed.data.customerId,
      plate_no: parsed.data.plateNo,
      brand: parsed.data.brand || null,
      model: parsed.data.model || null,
      year: parsed.data.year,
      vin: parsed.data.vin,
      last_odometer: parsed.data.lastOdometer,
      active: parsed.data.active,
    })
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) return { error: mapError(error.code) };
  if (!data || data.length === 0) {
    return { error: "Kendaraan tidak ditemukan atau bukan hak Anda." };
  }

  revalidatePath("/kendaraan");
  redirect("/kendaraan");
}

export async function deleteVehicleAction(
  _prev: VehicleActionState,
  formData: FormData
): Promise<VehicleActionState> {
  const parsed = deleteVehicleSchema.safeParse({
    tenantId: str(formData, "tenantId"),
    id: str(formData, "id"),
  });

  if (!parsed.success) return { error: "Data kendaraan tidak valid." };

  const ctx = await getWriterContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error };

  const { data, error } = await ctx.supabase
    .from("vehicles")
    .delete()
    .eq("tenant_id", parsed.data.tenantId)
    .eq("id", parsed.data.id)
    .select("id");

  if (error) {
    if (error.code === "23503") {
      return { error: "Kendaraan masih dipakai transaksi lain." };
    }
    return { error: "Gagal menghapus kendaraan." };
  }
  if (!data || data.length === 0) {
    return { error: "Kendaraan tidak ditemukan atau bukan hak Anda." };
  }

  revalidatePath("/kendaraan");
  redirect("/kendaraan");
}
