import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";

export type ShiftRow = {
  id: string;
  outletName: string;
  openedAt: string;
  closedAt: string | null;
  openingCash: number;
  closingCashCounted: number | null;
  expectedCash: number | null;
  difference: number | null;
  note: string | null;
  isOwn: boolean;
};

export type ShiftPageData = {
  tenantId: string;
  tenantName: string;
  canOpen: boolean;
  outlets: { id: string; name: string }[];
  currentUserId: string;
  currentShift: ShiftRow | null;
  shifts: ShiftRow[];
};

const CASHIER_ROLES = ["owner", "admin", "kasir"];

export async function getShiftPageData(): Promise<ShiftPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const [outletsRes, shiftsRes, openRes] = await Promise.all([
    supabase
      .from("outlets")
      .select("id, name")
      .eq("tenant_id", base.tenantId)
      .order("name"),
    supabase
      .from("cash_shifts")
      .select(
        "id, outlet_id, cashier_id, opened_at, closed_at, opening_cash, closing_cash_counted, expected_cash, difference, note"
      )
      .eq("tenant_id", base.tenantId)
      .order("opened_at", { ascending: false })
      .limit(20),
    supabase
      .from("cash_shifts")
      .select(
        "id, outlet_id, cashier_id, opened_at, closed_at, opening_cash, closing_cash_counted, expected_cash, difference, note"
      )
      .eq("tenant_id", base.tenantId)
      .eq("cashier_id", user.id)
      .is("closed_at", null)
      .order("opened_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
  ]);

  const outletNames = new Map(
    (outletsRes.data ?? []).map((outlet) => [outlet.id, outlet.name])
  );

  const toRow = (row: NonNullable<typeof openRes.data>): ShiftRow => ({
    id: row.id,
    outletName: outletNames.get(row.outlet_id) ?? "—",
    openedAt: row.opened_at,
    closedAt: row.closed_at,
    openingCash: Number(row.opening_cash),
    closingCashCounted:
      row.closing_cash_counted === null ? null : Number(row.closing_cash_counted),
    expectedCash: row.expected_cash === null ? null : Number(row.expected_cash),
    difference: row.difference === null ? null : Number(row.difference),
    note: row.note,
    isOwn: row.cashier_id === user.id,
  });

  let currentShift = openRes.data ? toRow(openRes.data) : null;

  if (currentShift) {
    const { data: expected } = await supabase.rpc("shift_expected_cash", {
      p_shift_id: currentShift.id,
    });
    if (expected !== null) {
      currentShift = { ...currentShift, expectedCash: Number(expected) };
    }
  }

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canOpen: CASHIER_ROLES.includes(base.role),
    outlets: outletsRes.data ?? [],
    currentUserId: user.id,
    currentShift,
    shifts: (shiftsRes.data ?? []).map(toRow),
  };
}
