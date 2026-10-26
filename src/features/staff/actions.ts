"use server";

import { revalidatePath } from "next/cache";

import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import {
  addStaffSchema,
  setStaffActiveSchema,
  updateStaffRoleSchema,
} from "./schema";

export type StaffActionState = {
  error: string | null;
  success: string | null;
};

type ManagerContext =
  | { ok: true; supabase: Awaited<ReturnType<typeof createClient>> }
  | { ok: false; error: string };

async function getManagerContext(tenantId: string): Promise<ManagerContext> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { ok: false, error: "Sesi tidak valid. Silakan login ulang." };

  const { data } = await supabase
    .from("memberships")
    .select("role")
    .eq("tenant_id", tenantId)
    .eq("user_id", user.id)
    .eq("active", true)
    .maybeSingle();

  if (!data || !["owner", "admin"].includes(data.role)) {
    return { ok: false, error: "Anda tidak berhak mengelola staf di usaha ini." };
  }

  return { ok: true, supabase };
}

export async function addStaffAction(
  _prev: StaffActionState,
  formData: FormData
): Promise<StaffActionState> {
  const parsed = addStaffSchema.safeParse({
    tenantId: formData.get("tenantId"),
    email: formData.get("email"),
    password: formData.get("password") ?? "",
    role: formData.get("role"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Isian staf belum lengkap.",
      success: null,
    };
  }

  const ctx = await getManagerContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const admin = createAdminClient();

  const { data: userList, error: listError } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (listError) {
    return { error: "Gagal memeriksa akun staf.", success: null };
  }

  const existing = userList.users.find(
    (u) => u.email?.toLowerCase() === parsed.data.email
  );

  let userId: string;
  let created = false;

  if (existing) {
    userId = existing.id;
  } else {
    const password = parsed.data.password ?? "";
    if (password.length < 8) {
      return {
        error: "Kata sandi sementara wajib diisi (minimal 8 karakter) untuk akun baru.",
        success: null,
      };
    }

    const { data: createdUser, error: createError } =
      await admin.auth.admin.createUser({
        email: parsed.data.email,
        password,
        email_confirm: true,
      });

    if (createError || !createdUser.user) {
      return { error: "Gagal membuat akun staf.", success: null };
    }

    userId = createdUser.user.id;
    created = true;
  }

  const { error: insertError } = await ctx.supabase.from("memberships").insert({
    tenant_id: parsed.data.tenantId,
    user_id: userId,
    role: parsed.data.role,
  });

  if (insertError) {
    if (created) {
      await admin.auth.admin.deleteUser(userId);
    }
    if (insertError.code === "23505") {
      return { error: "Email ini sudah terdaftar sebagai staf.", success: null };
    }
    if (insertError.code === "42501") {
      return {
        error: "Tidak berhak menambahkan staf dengan peran tersebut.",
        success: null,
      };
    }
    return { error: "Gagal menambahkan staf.", success: null };
  }

  revalidatePath("/pengaturan");

  return {
    error: null,
    success: created
      ? "Staf ditambahkan. Sampaikan kata sandi sementara kepada staf."
      : "Staf ditambahkan ke usaha.",
  };
}

export async function updateStaffRoleAction(
  _prev: StaffActionState,
  formData: FormData
): Promise<StaffActionState> {
  const parsed = updateStaffRoleSchema.safeParse({
    tenantId: formData.get("tenantId"),
    userId: formData.get("userId"),
    role: formData.get("role"),
  });

  if (!parsed.success) {
    return { error: "Data perubahan peran tidak valid.", success: null };
  }

  const ctx = await getManagerContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const { data, error } = await ctx.supabase
    .from("memberships")
    .update({ role: parsed.data.role })
    .eq("tenant_id", parsed.data.tenantId)
    .eq("user_id", parsed.data.userId)
    .select("id");

  if (error) {
    return { error: "Gagal mengubah peran staf.", success: null };
  }
  if (!data || data.length === 0) {
    return {
      error: "Tidak berhak mengubah staf ini (mis. baris owner oleh admin).",
      success: null,
    };
  }

  revalidatePath("/pengaturan");
  return { error: null, success: "Peran staf diperbarui." };
}

export async function setStaffActiveAction(
  _prev: StaffActionState,
  formData: FormData
): Promise<StaffActionState> {
  const parsed = setStaffActiveSchema.safeParse({
    tenantId: formData.get("tenantId"),
    userId: formData.get("userId"),
    active: formData.get("active"),
  });

  if (!parsed.success) {
    return { error: "Data status staf tidak valid.", success: null };
  }

  const ctx = await getManagerContext(parsed.data.tenantId);
  if (!ctx.ok) return { error: ctx.error, success: null };

  const active = parsed.data.active === "true";
  const { data, error } = await ctx.supabase
    .from("memberships")
    .update({ active })
    .eq("tenant_id", parsed.data.tenantId)
    .eq("user_id", parsed.data.userId)
    .select("id");

  if (error) {
    if (error.message.includes("Owner aktif terakhir")) {
      return { error: error.message, success: null };
    }
    return { error: "Gagal mengubah status staf.", success: null };
  }
  if (!data || data.length === 0) {
    return { error: "Tidak berhak mengubah status staf ini.", success: null };
  }

  revalidatePath("/pengaturan");
  return {
    error: null,
    success: active ? "Staf diaktifkan." : "Staf dinonaktifkan.",
  };
}
