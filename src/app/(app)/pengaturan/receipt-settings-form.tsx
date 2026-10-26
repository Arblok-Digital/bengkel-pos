"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  saveReceiptSettingsAction,
  type ReceiptSettingsState,
} from "@/features/sales/actions";
import type { ReceiptSettings } from "@/features/sales/queries";

const initialState: ReceiptSettingsState = { error: null, success: null };

export function ReceiptSettingsForm({
  tenantId,
  tenantName,
  settings,
}: {
  tenantId: string;
  tenantName: string;
  settings: ReceiptSettings;
}) {
  const [state, formAction, pending] = useActionState(
    saveReceiptSettingsAction,
    initialState
  );

  return (
    <section className="rounded-lg border bg-card p-4">
      <div>
        <h2 className="text-lg font-semibold">
          Struk &middot; {tenantName}
        </h2>
        <p className="text-muted-foreground mt-1 text-sm">
          Identitas toko, footer, dan lebar kertas untuk struk 58/80 mm.
        </p>
      </div>

      <form action={formAction} className="mt-4 grid gap-3 sm:grid-cols-2">
        <input type="hidden" name="tenantId" value={tenantId} />

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Nama toko di struk</span>
          <input
            name="storeName"
            defaultValue={settings.storeName}
            maxLength={80}
            placeholder={tenantName}
            className="h-11 rounded-md border border-input bg-background px-2"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Telepon</span>
          <input
            name="phone"
            defaultValue={settings.phone}
            maxLength={30}
            placeholder="cth: 0812-3456-7890"
            className="h-11 rounded-md border border-input bg-background px-2"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">Alamat</span>
          <input
            name="address"
            defaultValue={settings.address}
            maxLength={200}
            placeholder="cth: Jl. Raya No. 10, Bandung"
            className="h-11 rounded-md border border-input bg-background px-2"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">Footer struk</span>
          <textarea
            name="footer"
            defaultValue={settings.footer}
            maxLength={300}
            rows={2}
            placeholder="cth: Garansi servis 7 hari. Barang yang sudah dibeli tidak dapat ditukar."
            className="rounded-md border border-input bg-background p-2"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">URL logo (opsional)</span>
          <input
            name="logoUrl"
            defaultValue={settings.logoUrl}
            maxLength={300}
            placeholder="https://..."
            className="h-11 rounded-md border border-input bg-background px-2"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Lebar kertas default</span>
          <select
            name="paperWidth"
            defaultValue={settings.paperWidth}
            className="h-11 rounded-md border border-input bg-background px-2"
          >
            <option value="58">58 mm (thermal kecil)</option>
            <option value="80">80 mm (thermal besar)</option>
          </select>
        </label>

        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="hideTaxPercent"
            defaultChecked={settings.hideTaxPercent}
            className="h-5 w-5"
          />
          <span>Sembunyikan persen pajak di struk</span>
        </label>

        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="showMechanic"
            defaultChecked={settings.showMechanic}
            className="h-5 w-5"
          />
          <span>Tampilkan nama mekanik (bengkel)</span>
        </label>

        <div className="flex items-center gap-3 sm:col-span-2">
          <Button type="submit" disabled={pending} className="h-11 min-w-44">
            {pending ? "Menyimpan..." : "Simpan pengaturan struk"}
          </Button>
          {state.error ? (
            <p className="text-sm text-destructive" role="alert">
              {state.error}
            </p>
          ) : null}
          {state.success ? (
            <p className="text-sm text-green-700" role="status">
              {state.success}
            </p>
          ) : null}
        </div>
      </form>
    </section>
  );
}
