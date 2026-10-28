"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  updateWorkOrderStatusAction,
  type WorkOrderActionState,
} from "@/features/workorder/actions";

const initialState: WorkOrderActionState = { error: null };

const STATUS_LABEL: Record<string, string> = {
  antri: "Antrian",
  dikerjakan: "Dikerjakan",
  menunggu_part: "Menunggu Part",
  selesai: "Selesai",
  ditagih: "Ditagih",
  dibatalkan: "Dibatalkan",
};

const NEXT_STATUS: Record<string, string> = {
  antri: "dikerjakan",
  dikerjakan: "selesai",
  menunggu_part: "dikerjakan",
};

export function WorkOrderStatusForm({
  woId,
  status,
}: {
  woId: string;
  status: string;
}) {
  const [state, formAction, pending] = useActionState(
    updateWorkOrderStatusAction,
    initialState
  );

  const next = NEXT_STATUS[status];

  if (!next) return null;

  return (
    <form action={formAction} className="flex flex-wrap items-center gap-3">
      <input type="hidden" name="woId" value={woId} />
      <input type="hidden" name="status" value={next} />
      <Button type="submit" disabled={pending} className="min-h-11">
        {pending ? "Menyimpan..." : `Ubah ke ${STATUS_LABEL[next]}`}
      </Button>
      {state.error ? (
        <p className="text-sm text-destructive" role="alert">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
