import { redirect } from "next/navigation";

import { getMyTenants } from "@/features/tenant/queries";
import { OnboardingForm } from "./onboarding-form";

export default async function OnboardingPage() {
  const tenants = await getMyTenants();
  if (tenants.length > 0) {
    redirect("/");
  }

  const clientUuid = crypto.randomUUID();

  return (
    <div className="mx-auto flex max-w-md flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Buat Usaha</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          Isi data usaha dan outlet pertama. Anda akan menjadi pemilik (owner).
        </p>
      </div>
      <OnboardingForm clientUuid={clientUuid} />
    </div>
  );
}
