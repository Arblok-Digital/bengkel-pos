"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { getMyTenants, type TenantSummary, type BusinessType } from "./queries";

export type WorkspaceMode = "bengkel" | "toko";

export type Workspace = {
  tenantId: string;
  tenantName: string;
  businessType: BusinessType;
  mode: WorkspaceMode;
  role: string;
  outletId: string | null;
  outlets: { id: string; name: string }[];
  canWrite: boolean;
};

const COOKIE = "workspace";

function modesFor(bt: BusinessType): WorkspaceMode[] {
  if (bt === "bengkel") return ["bengkel"];
  if (bt === "toko_bangunan") return ["toko"];
  return ["bengkel", "toko"];
}

export async function modesForBusinessType(bt: BusinessType): Promise<WorkspaceMode[]> {
  return Promise.resolve(modesFor(bt));
}

export async function getWorkspace(): Promise<Workspace | null> {
  const tenants = await getMyTenants();
  if (tenants.length === 0) return null;

  const jar = await cookies();
  const raw = jar.get(COOKIE)?.value;
  let wantedTenant: string | null = null;
  let wantedMode: WorkspaceMode | null = null;
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as { tenantId?: string; mode?: string };
      wantedTenant = parsed.tenantId ?? null;
      wantedMode = (parsed.mode as WorkspaceMode) ?? null;
    } catch {
      wantedTenant = null;
    }
  }

  let tenant: TenantSummary | undefined = tenants.find((t) => t.tenantId === wantedTenant);
  if (!tenant) tenant = tenants[0];

  const allowed = modesFor(tenant.businessType);
  const mode: WorkspaceMode =
    wantedMode && allowed.includes(wantedMode) ? wantedMode : allowed[0];

  const outletId = tenant.outlets[0]?.id ?? null;
  const canWrite = tenant.role !== "viewer" && tenant.role !== "mekanik";

  return {
    tenantId: tenant.tenantId,
    tenantName: tenant.tenantName,
    businessType: tenant.businessType,
    mode,
    role: tenant.role,
    outletId,
    outlets: tenant.outlets,
    canWrite,
  };
}

export async function setWorkspaceAction(formData: FormData) {
  const tenantId = String(formData.get("tenantId") ?? "");
  const mode = String(formData.get("mode") ?? "") as WorkspaceMode;
  const tenants = await getMyTenants();
  const tenant = tenants.find((t) => t.tenantId === tenantId);
  if (!tenant) return;
  const allowed = modesFor(tenant.businessType);
  const safeMode = allowed.includes(mode) ? mode : allowed[0];

  const jar = await cookies();
  jar.set(COOKIE, JSON.stringify({ tenantId, mode: safeMode }), {
    path: "/",
    httpOnly: true,
    sameSite: "lax",
  });

  redirect("/");
}

export async function clearWorkspaceAction() {
  const jar = await cookies();
  jar.delete(COOKIE);
  redirect("/pilih-usaha");
}