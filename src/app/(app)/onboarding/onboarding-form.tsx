"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  createTenantAction,
  type OnboardingState,
} from "@/features/tenant/actions";

const initialState: OnboardingState = { error: null };

export function OnboardingForm({ clientUuid }: { clientUuid: string }) {
  const [state, formAction, pending] = useActionState(
    createTenantAction,
    initialState
  );

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="clientUuid" value={clientUuid} />

      <div className="flex flex-col gap-1">
        <label htmlFor="name" className="text-sm font-medium">
          Nama usaha
        </label>
        <input
          id="name"
          name="name"
          type="text"
          required
          maxLength={100}
          placeholder="Contoh: Bengkel Maju Jaya"
          className="h-10 rounded-md border border-input bg-background px-3 text-sm"
        />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="businessType" className="text-sm font-medium">
          Jenis usaha
        </label>
        <select
          id="businessType"
          name="businessType"
          required
          defaultValue="bengkel"
          className="h-10 rounded-md border border-input bg-background px-3 text-sm"
        >
          <option value="bengkel">Bengkel</option>
          <option value="toko_bangunan">Toko Bangunan</option>
          <option value="both">Bengkel &amp; Toko Bangunan</option>
        </select>
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="outletName" className="text-sm font-medium">
          Nama outlet pertama
        </label>
        <input
          id="outletName"
          name="outletName"
          type="text"
          required
          maxLength={100}
          placeholder="Contoh: Outlet Utama"
          className="h-10 rounded-md border border-input bg-background px-3 text-sm"
        />
      </div>

      {state.error ? (
        <p className="text-sm text-destructive" role="alert">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" disabled={pending} className="h-11">
        {pending ? "Menyimpan..." : "Buat Usaha"}
      </Button>
    </form>
  );
}
