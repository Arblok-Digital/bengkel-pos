import { redirect } from "next/navigation";

import { getWorkspace } from "@/features/tenant/workspace";

export default async function TokoLayout({ children }: { children: React.ReactNode }) {
  const ws = await getWorkspace();
  if (!ws || ws.mode !== "toko") redirect("/");
  return <>{children}</>;
}