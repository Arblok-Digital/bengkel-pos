import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";
import { parseReceiptSettings, type ReceiptSettings } from "@/features/sales/queries";

export type ReceivableStatus = "open" | "partial" | "paid";

export type ReceivableItem = {
  id: string;
  tenantId: string;
  saleId: string;
  invoiceNo: string;
  customerId: string;
  customerName: string;
  customerPhone: string | null;
  amount: number;
  totalPaid: number;
  remaining: number;
  dueDate: string;
  status: ReceivableStatus;
  createdAt: string;
  isOverdue: boolean;
};

export type ReceivablePaymentItem = {
  id: string;
  receivableId: string;
  amount: number;
  method: string;
  reference: string | null;
  paidAt: string;
  createdAt: string;
  createdBy: string | null;
};

export type ReceivablesSummary = {
  totalAmount: number;
  totalPaid: number;
  totalRemaining: number;
  countOpen: number;
  countOverdue: number;
};

export type ReceivablesPageData = {
  tenantId: string;
  tenantName: string;
  role: string;
  canWrite: boolean;
  receivables: ReceivableItem[];
  summary: ReceivablesSummary;
};

export type ReceivableDetailData = {
  receivable: ReceivableItem;
  sale: {
    id: string;
    invoiceNo: string;
    soldAt: string;
    total: number;
  };
  customer: {
    id: string;
    name: string;
    phone: string | null;
    address: string | null;
    creditLimit: number;
  };
  payments: ReceivablePaymentItem[];
  canWrite: boolean;
  tenantName: string;
  settings: ReceiptSettings;
};

export async function getReceivablesPage(filterStatus?: string): Promise<ReceivablesPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();

  let query = supabase
    .from("receivables")
    .select("id, tenant_id, sale_id, customer_id, amount, due_date, status, created_at")
    .eq("tenant_id", base.tenantId)
    .order("created_at", { ascending: false });

  if (filterStatus && ["open", "partial", "paid"].includes(filterStatus)) {
    query = query.eq("status", filterStatus);
  }

  const { data: recRows, error: recErr } = await query;
  if (recErr || !recRows) {
    return {
      tenantId: base.tenantId,
      tenantName: base.tenantName,
      role: base.role,
      canWrite: base.canWrite,
      receivables: [],
      summary: { totalAmount: 0, totalPaid: 0, totalRemaining: 0, countOpen: 0, countOverdue: 0 },
    };
  }

  const receivableIds = recRows.map((r) => r.id);
  const saleIds = Array.from(new Set(recRows.map((r) => r.sale_id)));
  const customerIds = Array.from(new Set(recRows.map((r) => r.customer_id)));

  const [salesRes, customersRes, paymentsRes] = await Promise.all([
    saleIds.length > 0
      ? supabase.from("sales").select("id, invoice_no").in("id", saleIds)
      : Promise.resolve({ data: [] }),
    customerIds.length > 0
      ? supabase.from("customers").select("id, name, phone").in("id", customerIds)
      : Promise.resolve({ data: [] }),
    receivableIds.length > 0
      ? supabase
          .from("receivable_payments")
          .select("id, receivable_id, amount, method, reference, paid_at, created_at, created_by")
          .in("receivable_id", receivableIds)
      : Promise.resolve({ data: [] }),
  ]);

  const salesMap = new Map((salesRes.data ?? []).map((s) => [s.id, s.invoice_no]));
  const customersMap = new Map(
    (customersRes.data ?? []).map((c) => [c.id, { name: c.name, phone: c.phone }])
  );

  const paymentsByRec = new Map<string, number>();
  for (const p of paymentsRes.data ?? []) {
    const prev = paymentsByRec.get(p.receivable_id) ?? 0;
    paymentsByRec.set(p.receivable_id, prev + Number(p.amount));
  }

  const todayStr = new Date().toISOString().slice(0, 10);

  let totalAmount = 0;
  let totalPaid = 0;
  let totalRemaining = 0;
  let countOpen = 0;
  let countOverdue = 0;

  const receivables: ReceivableItem[] = recRows.map((r) => {
    const cust = customersMap.get(r.customer_id);
    const originalAmount = Number(r.amount);
    const paid = paymentsByRec.get(r.id) ?? 0;
    const remaining = Math.max(0, originalAmount - paid);
    const isOverdue = r.due_date < todayStr && r.status !== "paid";

    totalAmount += originalAmount;
    totalPaid += paid;
    totalRemaining += remaining;
    if (r.status !== "paid") countOpen++;
    if (isOverdue) countOverdue++;

    return {
      id: r.id,
      tenantId: r.tenant_id,
      saleId: r.sale_id,
      invoiceNo: salesMap.get(r.sale_id) ?? "—",
      customerId: r.customer_id,
      customerName: cust?.name ?? "—",
      customerPhone: cust?.phone ?? null,
      amount: originalAmount,
      totalPaid: paid,
      remaining,
      dueDate: r.due_date,
      status: r.status as ReceivableStatus,
      createdAt: r.created_at,
      isOverdue,
    };
  });

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    role: base.role,
    canWrite: base.canWrite,
    receivables,
    summary: {
      totalAmount,
      totalPaid,
      totalRemaining,
      countOpen,
      countOverdue,
    },
  };
}

export async function getReceivableDetail(id: string): Promise<ReceivableDetailData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();

  const { data: rec, error } = await supabase
    .from("receivables")
    .select("id, tenant_id, sale_id, customer_id, amount, due_date, status, created_at")
    .eq("id", id)
    .eq("tenant_id", base.tenantId)
    .maybeSingle();

  if (error || !rec) return null;

  const [saleRes, custRes, paymentsRes, tenantRes] = await Promise.all([
    supabase
      .from("sales")
      .select("id, invoice_no, sold_at, total")
      .eq("id", rec.sale_id)
      .maybeSingle(),
    supabase
      .from("customers")
      .select("id, name, phone, address, credit_limit")
      .eq("id", rec.customer_id)
      .maybeSingle(),
    supabase
      .from("receivable_payments")
      .select("id, receivable_id, amount, method, reference, paid_at, created_at, created_by")
      .eq("receivable_id", rec.id)
      .order("paid_at", { ascending: true }),
    supabase
      .from("tenants")
      .select("settings")
      .eq("id", base.tenantId)
      .maybeSingle(),
  ]);

  const sale = saleRes.data;
  const customer = custRes.data;
  const payments: ReceivablePaymentItem[] = (paymentsRes.data ?? []).map((p) => ({
    id: p.id,
    receivableId: p.receivable_id,
    amount: Number(p.amount),
    method: p.method,
    reference: p.reference,
    paidAt: p.paid_at,
    createdAt: p.created_at,
    createdBy: p.created_by,
  }));

  const totalPaid = payments.reduce((acc, p) => acc + p.amount, 0);
  const originalAmount = Number(rec.amount);
  const remaining = Math.max(0, originalAmount - totalPaid);
  const todayStr = new Date().toISOString().slice(0, 10);
  const isOverdue = rec.due_date < todayStr && rec.status !== "paid";

  const settings = parseReceiptSettings(tenantRes.data?.settings, base.tenantName);

  return {
    receivable: {
      id: rec.id,
      tenantId: rec.tenant_id,
      saleId: rec.sale_id,
      invoiceNo: sale?.invoice_no ?? "—",
      customerId: rec.customer_id,
      customerName: customer?.name ?? "—",
      customerPhone: customer?.phone ?? null,
      amount: originalAmount,
      totalPaid,
      remaining,
      dueDate: rec.due_date,
      status: rec.status as ReceivableStatus,
      createdAt: rec.created_at,
      isOverdue,
    },
    sale: {
      id: rec.sale_id,
      invoiceNo: sale?.invoice_no ?? "—",
      soldAt: sale?.sold_at ?? rec.created_at,
      total: Number(sale?.total ?? rec.amount),
    },
    customer: {
      id: rec.customer_id,
      name: customer?.name ?? "Pelanggan",
      phone: customer?.phone ?? null,
      address: customer?.address ?? null,
      creditLimit: Number(customer?.credit_limit ?? 0),
    },
    payments,
    canWrite: base.canWrite,
    tenantName: base.tenantName,
    settings,
  };
}
