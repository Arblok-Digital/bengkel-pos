import { redirect } from "next/navigation";

import { getWorkspace } from "@/features/tenant/workspace";

export default async function DashboardPage() {
  const workspace = await getWorkspace();
  if (!workspace) redirect("/onboarding");

  redirect(workspace.mode === "bengkel" ? "/bengkel" : "/toko");
}
