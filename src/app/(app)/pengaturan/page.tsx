import { redirect } from "next/navigation";

import {
  getCurrentUserId,
  getManagerTenants,
  getStaff,
} from "@/features/staff/queries";
import { StaffManager } from "./staff-manager";

export default async function SettingsPage() {
  const [tenants, currentUserId] = await Promise.all([
    getManagerTenants(),
    getCurrentUserId(),
  ]);

  if (!currentUserId || tenants.length === 0) {
    redirect("/");
  }

  const sections = await Promise.all(
    tenants.map(async (tenant) => ({
      ...tenant,
      staff: await getStaff(tenant.tenantId, currentUserId),
    }))
  );

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Pengaturan</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          Kelola staf, peran, dan status aktif. Hanya pemilik/admin yang dapat
          membuka halaman ini.
        </p>
      </div>

      {sections.map((section) => (
        <StaffManager
          key={section.tenantId}
          tenantId={section.tenantId}
          tenantName={section.tenantName}
          staff={section.staff}
        />
      ))}
    </div>
  );
}
