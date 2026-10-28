"use client";

import { useActionState, useEffect, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  createVehicleAction,
  type VehicleActionState,
} from "@/features/vehicles/actions";
import { getCustomerOptions } from "@/features/vehicles/queries";

const initialState: VehicleActionState = { error: null };

export function VehicleForm() {
  const [customers, setCustomers] = useState<{ id: string; name: string }[]>(
    []
  );
  const [state, formAction, pending] = useActionState(
    createVehicleAction,
    initialState
  );

  useEffect(() => {
    getCustomerOptions().then(setCustomers);
  }, []);

  return (
    <form action={formAction} className="rounded-lg border bg-card p-4 space-y-4">
      <input type="hidden" name="active" value="on" />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Pelanggan</span>
          <select
            name="customerId"
            required
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="">Pilih pelanggan</option>
            {customers.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Nomor Polisi</span>
          <input
            name="plateNo"
            placeholder="Contoh: B 1234 ABC"
            className="h-9 rounded-md border border-input bg-background px-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">Merk</span>
          <input
            name="brand"
            placeholder="Contoh: Toyota"
            className="h-9 rounded-md border border-input bg-background px-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Model</span>
          <input
            name="model"
            placeholder="Contoh: Avanza"
            className="h-9 rounded-md border border-input bg-background px-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Tahun</span>
          <input
            name="year"
            type="number"
            min="1900"
            max="2100"
            className="h-9 rounded-md border border-input bg-background px-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">VIN / Rangka</span>
          <input
            name="vin"
            placeholder="Opsional"
            className="h-9 rounded-md border border-input bg-background px-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Odometer Terakhir (km)</span>
          <input
            name="lastOdometer"
            type="number"
            min="0"
            className="h-9 rounded-md border border-input bg-background px-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm sm:col-span-2">
          <span className="font-medium">Status</span>
          <select
            name="active"
            className="h-9 rounded-md border border-input bg-background px-2"
          >
            <option value="on">Aktif</option>
            <option value="off">Nonaktif</option>
          </select>
        </label>
      </div>

      <div className="mt-4 flex items-center gap-3">
        <Button type="submit" disabled={pending} className="h-9">
          {pending ? "Menyimpan..." : "Simpan Kendaraan"}
        </Button>
        {state.error ? (
          <p className="text-sm text-destructive" role="alert">
            {state.error}
          </p>
        ) : null}
      </div>
    </form>
  );
}
