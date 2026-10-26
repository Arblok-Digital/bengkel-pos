"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  addStaffAction,
  setStaffActiveAction,
  updateStaffRoleAction,
  type StaffActionState,
} from "@/features/staff/actions";
import type { StaffMember } from "@/features/staff/queries";

const initialState: StaffActionState = { error: null, success: null };

const roleOptions = [
  { value: "admin", label: "Admin" },
  { value: "kasir", label: "Kasir" },
  { value: "mekanik", label: "Mekanik" },
  { value: "gudang", label: "Gudang" },
] as const;

const roleLabel: Record<string, string> = {
  owner: "Pemilik",
  admin: "Admin",
  kasir: "Kasir",
  mekanik: "Mekanik",
  gudang: "Gudang",
  dev: "Operator",
};

type Props = {
  tenantId: string;
  tenantName: string;
  staff: StaffMember[];
};

export function StaffManager({ tenantId, tenantName, staff }: Props) {
  return (
    <section className="rounded-lg border bg-card p-4">
      <h2 className="text-lg font-semibold">{tenantName}</h2>

      <AddStaffForm tenantId={tenantId} />

      <div className="mt-4 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="py-2 pr-3 font-medium">Staf</th>
              <th className="py-2 pr-3 font-medium">Peran</th>
              <th className="py-2 pr-3 font-medium">Status</th>
              <th className="py-2 font-medium">Aksi</th>
            </tr>
          </thead>
          <tbody>
            {staff.map((member) => (
              <StaffRow
                key={member.userId}
                tenantId={tenantId}
                member={member}
              />
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function AddStaffForm({ tenantId }: { tenantId: string }) {
  const [state, formAction, pending] = useActionState(
    addStaffAction,
    initialState
  );

  return (
    <form
      action={formAction}
      className="mt-4 flex flex-col gap-3 rounded-md border bg-background p-3 sm:flex-row sm:items-end"
    >
      <input type="hidden" name="tenantId" value={tenantId} />

      <label className="flex flex-1 flex-col gap-1 text-sm">
        <span className="font-medium">Email staf</span>
        <input
          name="email"
          type="email"
          required
          autoComplete="off"
          placeholder="staf@contoh.com"
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-1 flex-col gap-1 text-sm">
        <span className="font-medium">Kata sandi sementara</span>
        <input
          name="password"
          type="password"
          minLength={8}
          autoComplete="new-password"
          placeholder="Wajib untuk akun baru"
          className="h-9 rounded-md border border-input bg-background px-2"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium">Peran</span>
        <select
          name="role"
          defaultValue="kasir"
          className="h-9 rounded-md border border-input bg-background px-2"
        >
          {roleOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </label>

      <Button type="submit" disabled={pending} className="h-9">
        {pending ? "Menambah..." : "Tambah staf"}
      </Button>

      {state.error ? (
        <p className="w-full text-sm text-destructive" role="alert">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p className="w-full text-sm text-green-700" role="status">
          {state.success}
        </p>
      ) : null}
    </form>
  );
}

function StaffRow({
  tenantId,
  member,
}: {
  tenantId: string;
  member: StaffMember;
}) {
  const [roleState, roleAction, rolePending] = useActionState(
    updateStaffRoleAction,
    initialState
  );
  const [activeState, activeAction, activePending] = useActionState(
    setStaffActiveAction,
    initialState
  );

  const canEdit =
    !member.isSelf && member.role !== "owner" && member.role !== "dev";

  return (
    <tr className="border-b last:border-0 align-top">
      <td className="py-2 pr-3">
        {member.email}
        {member.isSelf ? (
          <span className="text-muted-foreground"> (Anda)</span>
        ) : null}
      </td>

      <td className="py-2 pr-3">
        {canEdit ? (
          <form action={roleAction} className="flex items-center gap-2">
            <input type="hidden" name="tenantId" value={tenantId} />
            <input type="hidden" name="userId" value={member.userId} />
            <select
              name="role"
              defaultValue={member.role}
              aria-label={`Peran ${member.email}`}
              className="h-8 rounded-md border border-input bg-background px-2"
            >
              {roleOptions.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
            <Button type="submit" size="sm" disabled={rolePending}>
              Simpan
            </Button>
          </form>
        ) : (
          (roleLabel[member.role] ?? member.role)
        )}
      </td>

      <td className="py-2 pr-3">
        {member.active ? (
          "Aktif"
        ) : (
          <span className="font-semibold text-destructive">Nonaktif</span>
        )}
      </td>

      <td className="py-2">
        {canEdit ? (
          <form action={activeAction}>
            <input type="hidden" name="tenantId" value={tenantId} />
            <input type="hidden" name="userId" value={member.userId} />
            <input
              type="hidden"
              name="active"
              value={member.active ? "false" : "true"}
            />
            <Button
              type="submit"
              variant="outline"
              size="sm"
              disabled={activePending}
            >
              {member.active ? "Nonaktifkan" : "Aktifkan"}
            </Button>
          </form>
        ) : (
          <span className="text-muted-foreground">—</span>
        )}

        {roleState.error || activeState.error ? (
          <p className="mt-1 text-destructive" role="alert">
            {roleState.error ?? activeState.error}
          </p>
        ) : null}
        {roleState.success || activeState.success ? (
          <p className="mt-1 text-green-700" role="status">
            {roleState.success ?? activeState.success}
          </p>
        ) : null}
      </td>
    </tr>
  );
}
