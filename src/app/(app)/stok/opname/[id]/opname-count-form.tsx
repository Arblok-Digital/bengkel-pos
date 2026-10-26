"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  postOpnameAction,
  saveOpnameCountsAction,
  type OpnameActionState,
} from "@/features/inventory/actions";
import type { OpnameItemRow } from "@/features/inventory/queries";

const initialState: OpnameActionState = { error: null, success: null };

function formatQty(value: number): string {
  return value.toLocaleString("id-ID", { maximumFractionDigits: 3 });
}

export function OpnameCountForm({
  tenantId,
  opnameId,
  items,
}: {
  tenantId: string;
  opnameId: string;
  items: OpnameItemRow[];
}) {
  const [saveState, saveAction, savePending] = useActionState(
    saveOpnameCountsAction,
    initialState
  );
  const [postState, postAction, postPending] = useActionState(
    postOpnameAction,
    initialState
  );

  return (
    <div className="flex flex-col gap-4">
      <form action={saveAction} className="rounded-lg border bg-card p-4">
        <input type="hidden" name="tenantId" value={tenantId} />
        <input type="hidden" name="opnameId" value={opnameId} />

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="p-2 font-medium">Produk</th>
                <th className="p-2 font-medium">Stok sistem</th>
                <th className="p-2 font-medium">Hitungan fisik</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item) => (
                <tr key={item.id} className="border-b last:border-0">
                  <td className="p-2">{item.productName}</td>
                  <td className="p-2">{formatQty(item.systemQty)}</td>
                  <td className="p-2">
                    <input
                      name={`count_${item.id}`}
                      type="number"
                      min={0}
                      step={0.001}
                      defaultValue={item.countedQty ?? ""}
                      aria-label={`Hitungan ${item.productName}`}
                      className="h-8 w-28 rounded-md border border-input bg-background px-2"
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="mt-4 flex items-center gap-3">
          <Button type="submit" disabled={savePending} className="h-9">
            {savePending ? "Menyimpan..." : "Simpan hitungan"}
          </Button>
          {saveState.error ? (
            <p className="text-sm text-destructive" role="alert">
              {saveState.error}
            </p>
          ) : null}
          {saveState.success ? (
            <p className="text-sm text-green-700" role="status">
              {saveState.success}
            </p>
          ) : null}
        </div>
      </form>

      <form
        action={postAction}
        className="rounded-lg border bg-card p-4 text-sm"
      >
        <input type="hidden" name="tenantId" value={tenantId} />
        <input type="hidden" name="opnameId" value={opnameId} />
        <p className="text-muted-foreground">
          Posting akan membandingkan hitungan dengan stok terkini dan membuat
          movement <strong>opname</strong>. Simpan hitungan dulu sebelum
          posting.
        </p>
        <div className="mt-3 flex items-center gap-3">
          <Button
            type="submit"
            variant="destructive"
            disabled={postPending}
            className="h-9"
          >
            {postPending ? "Memposting..." : "Posting opname"}
          </Button>
          {postState.error ? (
            <p className="text-sm text-destructive" role="alert">
              {postState.error}
            </p>
          ) : null}
        </div>
      </form>
    </div>
  );
}
