import { createClient } from "@/lib/supabase/server";
import { getCatalog } from "@/features/catalog/queries";

export type PurchaseOrderRow = {
  id: string;
  poNo: string;
  supplierId: string;
  supplierName: string;
  outletId: string;
  outletName: string;
  status: "draft" | "ordered" | "partial" | "received" | "cancelled";
  total: number;
  createdAt: string;
};

export type PurchaseOrderItemRow = {
  id: string;
  productId: string;
  productName: string;
  unitId: string;
  unitName: string;
  qty: number;
  qtyBase: number;
  unitPrice: number;
  lineTotal: number;
  note: string | null;
};

export type PurchaseOrderPageData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  purchaseOrders: PurchaseOrderRow[];
};

export type PurchaseOrderDetail = PurchaseOrderRow & {
  items: PurchaseOrderItemRow[];
  note: string | null;
};

function mapPurchaseOrder(row: {
  id: string;
  po_no: string;
  supplier_id: string;
  supplier_name: string | null;
  outlet_id: string;
  outlet_name: string | null;
  status: string;
  total: number | string;
  created_at: string;
}): PurchaseOrderRow {
  return {
    id: row.id,
    poNo: row.po_no,
    supplierId: row.supplier_id,
    supplierName: row.supplier_name ?? "—",
    outletId: row.outlet_id,
    outletName: row.outlet_name ?? "—",
    status: (row.status ?? "draft") as PurchaseOrderRow["status"],
    total: Number(row.total),
    createdAt: row.created_at,
  };
}

function mapPurchaseOrderItem(row: {
  id: string;
  product_id: string;
  product_name: string | null;
  unit_id: string;
  unit_name: string | null;
  qty: number | string;
  qty_base: number | string;
  unit_price: number | string;
  line_total: number | string;
  note: string | null;
}): PurchaseOrderItemRow {
  return {
    id: row.id,
    productId: row.product_id,
    productName: row.product_name ?? "—",
    unitId: row.unit_id,
    unitName: row.unit_name ?? "—",
    qty: Number(row.qty),
    qtyBase: Number(row.qty_base),
    unitPrice: Number(row.unit_price),
    lineTotal: Number(row.line_total),
    note: row.note,
  };
}

export async function getPurchaseOrdersPage(): Promise<PurchaseOrderPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("purchase_orders")
    .select(
      "id, po_no, supplier_id, outlet_id, status, total, created_at, suppliers(name), outlets(name)"
    )
    .eq("tenant_id", base.tenantId)
    .order("created_at", { ascending: false });

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    purchaseOrders: (data ?? []).map((row) => {
      const r = row as unknown as {
        id: string;
        po_no: string;
        supplier_id: string;
        outlet_id: string;
        status: string;
        total: number | string;
        created_at: string;
        suppliers: { name: string | null } | null;
        outlets: { name: string | null } | null;
      };
      return mapPurchaseOrder({
        ...r,
        supplier_name: r.suppliers?.name ?? null,
        outlet_name: r.outlets?.name ?? null,
      });
    }),
  };
}

export async function getPurchaseOrderForEdit(
  id: string
): Promise<PurchaseOrderDetail | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data: po } = await supabase
    .from("purchase_orders")
    .select(
      "id, po_no, supplier_id, outlet_id, status, total, note, created_at, suppliers(name), outlets(name)"
    )
    .eq("tenant_id", base.tenantId)
    .eq("id", id)
    .maybeSingle();

  if (!po) return null;

  const { data: items } = await supabase
    .from("purchase_order_items")
    .select(
      "id, product_id, unit_id, qty, qty_base, unit_price, line_total, note, products(name), units(name)"
    )
    .eq("tenant_id", base.tenantId)
    .eq("purchase_order_id", id)
    .order("created_at", { ascending: true });

  const r = po as unknown as {
    id: string;
    po_no: string;
    supplier_id: string;
    outlet_id: string;
    status: string;
    total: number | string;
    note: string | null;
    created_at: string;
    suppliers: { name: string | null } | null;
    outlets: { name: string | null } | null;
  };

  const main: PurchaseOrderRow = mapPurchaseOrder({
    ...r,
    supplier_name: r.suppliers?.name ?? null,
    outlet_name: r.outlets?.name ?? null,
  });

  const itemRows = items ?? [];
  const itemDetail: PurchaseOrderItemRow[] = itemRows.map((row) => {
    const it = row as unknown as {
      id: string;
      product_id: string;
      product_name: string | null;
      unit_id: string;
      unit_name: string | null;
      qty: number | string;
      qty_base: number | string;
      unit_price: number | string;
      line_total: number | string;
      note: string | null;
    };
    return mapPurchaseOrderItem(it);
  });

  return { ...main, note: r.note, items: itemDetail };
}

export type SupplierSelectOption = { id: string; name: string };

export async function getSupplierOptions(): Promise<SupplierSelectOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("suppliers")
    .select("id, name")
    .eq("tenant_id", base.tenantId)
    .eq("active", true)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
  }));
}

export type ProductSelectOption = { id: string; name: string; baseUnitId: string | null };

export async function getProductOptions(): Promise<ProductSelectOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("products")
    .select("id, name, base_unit_id")
    .eq("tenant_id", base.tenantId)
    .eq("active", true)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
    baseUnitId: row.base_unit_id,
  }));
}

export type UnitSelectOption = { id: string; name: string };

export async function getUnitOptions(): Promise<UnitSelectOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("units")
    .select("id, name")
    .eq("tenant_id", base.tenantId)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
  }));
}

export type OutletSelectOption = { id: string; name: string };

export async function getOutletOptions(): Promise<OutletSelectOption[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("outlets")
    .select("id, name")
    .eq("tenant_id", base.tenantId)
    .order("name");

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
  }));
}

export type GoodsReceiptRow = {
  id: string;
  grNo: string;
  supplierId: string;
  supplierName: string;
  outletId: string;
  outletName: string;
  purchaseOrderId: string | null;
  poNo: string | null;
  status: "draft" | "received" | "cancelled";
  total: number;
  createdAt: string;
};

export type GoodsReceiptItemRow = {
  id: string;
  productId: string;
  productName: string;
  unitId: string;
  unitName: string;
  qty: number;
  qtyBase: number;
  unitCost: number;
  lineTotal: number;
  note: string | null;
};

export type GoodsReceiptsPageData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  goodsReceipts: GoodsReceiptRow[];
};

export type GoodsReceiptDetail = GoodsReceiptRow & {
  items: GoodsReceiptItemRow[];
  note: string | null;
};

function mapGoodsReceipt(row: {
  id: string;
  gr_no: string;
  supplier_id: string;
  supplier_name: string | null;
  outlet_id: string;
  outlet_name: string | null;
  purchase_order_id: string | null;
  po_no: string | null;
  status: string;
  total: number | string;
  created_at: string;
}): GoodsReceiptRow {
  return {
    id: row.id,
    grNo: row.gr_no,
    supplierId: row.supplier_id,
    supplierName: row.supplier_name ?? "—",
    outletId: row.outlet_id,
    outletName: row.outlet_name ?? "—",
    purchaseOrderId: row.purchase_order_id,
    poNo: row.po_no,
    status: (row.status ?? "received") as GoodsReceiptRow["status"],
    total: Number(row.total),
    createdAt: row.created_at,
  };
}

function mapGoodsReceiptItem(row: {
  id: string;
  product_id: string;
  product_name: string | null;
  unit_id: string;
  unit_name: string | null;
  qty: number | string;
  qty_base: number | string;
  unit_cost: number | string;
  line_total: number | string;
  note: string | null;
}): GoodsReceiptItemRow {
  return {
    id: row.id,
    productId: row.product_id,
    productName: row.product_name ?? "—",
    unitId: row.unit_id,
    unitName: row.unit_name ?? "—",
    qty: Number(row.qty),
    qtyBase: Number(row.qty_base),
    unitCost: Number(row.unit_cost),
    lineTotal: Number(row.line_total),
    note: row.note,
  };
}

export async function getGoodsReceiptsPage(): Promise<GoodsReceiptsPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("goods_receipts")
    .select(
      "id, gr_no, supplier_id, outlet_id, purchase_order_id, status, total, created_at, suppliers(name), outlets(name), purchase_orders(po_no)"
    )
    .eq("tenant_id", base.tenantId)
    .order("created_at", { ascending: false });

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    goodsReceipts: (data ?? []).map((row) => {
      const r = row as unknown as {
        id: string;
        gr_no: string;
        supplier_id: string;
        outlet_id: string;
        purchase_order_id: string | null;
        status: string;
        total: number | string;
        created_at: string;
        suppliers: { name: string | null } | null;
        outlets: { name: string | null } | null;
        purchase_orders: { po_no: string | null } | null;
      };
      return mapGoodsReceipt({
        ...r,
        supplier_name: r.suppliers?.name ?? null,
        outlet_name: r.outlets?.name ?? null,
        po_no: r.purchase_orders?.po_no ?? null,
      });
    }),
  };
}

export async function getGoodsReceiptForEdit(
  id: string
): Promise<GoodsReceiptDetail | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data: gr } = await supabase
    .from("goods_receipts")
    .select(
      "id, gr_no, supplier_id, outlet_id, purchase_order_id, status, total, note, created_at, suppliers(name), outlets(name), purchase_orders(po_no)"
    )
    .eq("tenant_id", base.tenantId)
    .eq("id", id)
    .maybeSingle();

  if (!gr) return null;

  const { data: items } = await supabase
    .from("goods_receipt_items")
    .select(
      "id, product_id, unit_id, qty, qty_base, unit_cost, line_total, note, products(name), units(name)"
    )
    .eq("tenant_id", base.tenantId)
    .eq("goods_receipt_id", id)
    .order("created_at", { ascending: true });

  const r = gr as unknown as {
    id: string;
    gr_no: string;
    supplier_id: string;
    outlet_id: string;
    purchase_order_id: string | null;
    status: string;
    total: number | string;
    note: string | null;
    created_at: string;
    suppliers: { name: string | null } | null;
    outlets: { name: string | null } | null;
    purchase_orders: { po_no: string | null } | null;
  };

  const main: GoodsReceiptRow = mapGoodsReceipt({
    ...r,
    supplier_name: r.suppliers?.name ?? null,
    outlet_name: r.outlets?.name ?? null,
    po_no: r.purchase_orders?.po_no ?? null,
  });

  const itemRows = items ?? [];
  const itemDetail: GoodsReceiptItemRow[] = itemRows.map((row) => {
    const it = row as unknown as {
      id: string;
      product_id: string;
      product_name: string | null;
      unit_id: string;
      unit_name: string | null;
      qty: number | string;
      qty_base: number | string;
      unit_cost: number | string;
      line_total: number | string;
      note: string | null;
    };
    return mapGoodsReceiptItem(it);
  });

  return { ...main, note: r.note, items: itemDetail };
}

export type PoItemForReceiving = {
  id: string;
  productId: string;
  productName: string;
  unitId: string;
  unitName: string;
  poQtyBase: number;
  receivedQtyBase: number;
  remainingQtyBase: number;
  unitCost: number;
};

/** Item PO yang masih bisa diterima (sisa qty > 0). */
export async function getPoItemsForReceiving(
  purchaseOrderId: string
): Promise<PoItemForReceiving[]> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();

  const { data: poItems } = await supabase
    .from("purchase_order_items")
    .select(
      "id, product_id, unit_id, qty_base, unit_price, products(name), units(name)"
    )
    .eq("tenant_id", base.tenantId)
    .eq("purchase_order_id", purchaseOrderId);

  if (!poItems || poItems.length === 0) return [];

  const { data: receivedRows } = await supabase
    .from("goods_receipt_items")
    .select("product_id, unit_id, qty_base, goods_receipts(purchase_order_id)")
    .eq("tenant_id", base.tenantId);

  const receivedMap = new Map<string, number>();
  const key = (pid: string, uid: string) => `${pid}:${uid}`;
  for (const row of receivedRows ?? []) {
    const gr = (row as Record<string, unknown>)?.goods_receipts as
      | { purchase_order_id: string }
      | null;
    if (!gr || gr.purchase_order_id !== purchaseOrderId) continue;
    const k = key(row.product_id, row.unit_id);
    receivedMap.set(k, (receivedMap.get(k) ?? 0) + Number(row.qty_base));
  }

  const poItemList = poItems as unknown as {
    id: string;
    product_id: string;
    unit_id: string;
    qty_base: number | string;
    unit_price: number | string | null;
    products: { name: string } | null;
    units: { name: string } | null;
  }[];

  return poItemList.map((i) => {
    const k = key(i.product_id, i.unit_id);
    const receivedQtyBase = receivedMap.get(k) ?? 0;
    const poQtyBase = Number(i.qty_base);
    return {
      id: i.id,
      productId: i.product_id,
      productName: i.products?.name ?? "—",
      unitId: i.unit_id,
      unitName: i.units?.name ?? "—",
      poQtyBase,
      receivedQtyBase,
      remainingQtyBase: Math.max(0, poQtyBase - receivedQtyBase),
      unitCost: Number(i.unit_price ?? 0),
    };
  });
}

export type PurchaseOrderSelectOption = {
  id: string;
  poNo: string;
  supplierName: string;
};

/** PO yang statusnya masih bisa diterima (belum selesai). */
export async function getReceivablePurchaseOrders(): Promise<
  PurchaseOrderSelectOption[]
> {
  const base = await getCatalog();
  if (!base) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("purchase_orders")
    .select(
      "id, po_no, suppliers(name), status"
    )
    .eq("tenant_id", base.tenantId)
    .in("status", ["draft", "ordered", "partial"])
    .order("created_at", { ascending: false });

  return (data ?? []).map((row) => {
    const r = row as unknown as {
      id: string;
      po_no: string;
      suppliers: { name: string | null } | null;
      status: string;
    };
    return {
      id: r.id,
      poNo: r.po_no,
      supplierName: r.suppliers?.name ?? "—",
    };
  });
}

export type PayableStatus = "open" | "partial" | "paid";

export type PayableRow = {
  id: string;
  tenantId: string;
  outletId: string;
  supplierId: string;
  supplierName: string;
  purchaseOrderId: string | null;
  poNo: string | null;
  clientUuid: string;
  amount: number;
  totalPaid: number;
  remaining: number;
  dueDate: string;
  status: PayableStatus;
  createdAt: string;
};

export type PayablePaymentRow = {
  id: string;
  payableId: string;
  clientUuid: string;
  amount: number;
  method: string;
  reference: string | null;
  paidAt: string;
  createdAt: string;
};

export type PayablesPageData = {
  tenantId: string;
  tenantName: string;
  canWrite: boolean;
  payables: PayableRow[];
  summary: {
    totalAmount: number;
    totalPaid: number;
    totalRemaining: number;
    countOpen: number;
    countOverdue: number;
  };
};

export type PayableDetail = PayableRow & {
  payments: PayablePaymentRow[];
};

function mapPayable(row: {
  id: string;
  tenant_id: string;
  outlet_id: string;
  supplier_id: string;
  supplier_name: string | null;
  purchase_order_id: string | null;
  client_uuid: string;
  amount: number | string;
  total_paid: number | string;
  due_date: string;
  status: string;
  created_at: string;
}): PayableRow {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    outletId: row.outlet_id,
    supplierId: row.supplier_id,
    supplierName: row.supplier_name ?? "—",
    purchaseOrderId: row.purchase_order_id,
    poNo: null,
    clientUuid: row.client_uuid,
    amount: Number(row.amount),
    totalPaid: Number(row.total_paid),
    remaining: Math.max(0, Number(row.amount) - Number(row.total_paid)),
    dueDate: row.due_date,
    status: (row.status ?? "open") as PayableStatus,
    createdAt: row.created_at,
  };
}

export async function getPayablesPage(filterStatus?: string): Promise<PayablesPageData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();

  let query = supabase
    .from("payables")
    .select(
      "id, tenant_id, outlet_id, supplier_id, purchase_order_id, client_uuid, amount, total_paid, due_date, status, created_at, suppliers(name)"
    )
    .eq("tenant_id", base.tenantId)
    .order("created_at", { ascending: false });

  if (filterStatus && ["open", "partial", "paid"].includes(filterStatus)) {
    query = query.eq("status", filterStatus);
  }

  const { data: payableRows, error } = await query;
  if (error || !payableRows) {
    return {
      tenantId: base.tenantId,
      tenantName: base.tenantName,
      canWrite: base.canWrite,
      payables: [],
      summary: { totalAmount: 0, totalPaid: 0, totalRemaining: 0, countOpen: 0, countOverdue: 0 },
    };
  }

  const todayStr = new Date().toISOString().slice(0, 10);
  const poIds = Array.from(new Set(payableRows.map((r) => r.purchase_order_id).filter(Boolean)));

  const [poRes] = await Promise.all([
    poIds.length > 0
      ? supabase.from("purchase_orders").select("id, po_no").in("id", poIds)
      : Promise.resolve({ data: [] }),
  ]);

  const poMap = new Map((poRes.data ?? []).map((p) => [p.id, p.po_no]));

  let totalAmount = 0;
  let totalPaid = 0;
  let totalRemaining = 0;
  let countOpen = 0;
  let countOverdue = 0;

  const payables: PayableRow[] = payableRows.map((r) => {
    const rr = r as unknown as {
      id: string;
      tenant_id: string;
      outlet_id: string;
      supplier_id: string;
      purchase_order_id: string | null;
      client_uuid: string;
      amount: number | string;
      total_paid: number | string;
      due_date: string;
      status: string;
      created_at: string;
      suppliers: { name: string | null } | null;
    };
    const amount = Number(rr.amount);
    const paid = Number(rr.total_paid);
    const remaining = Math.max(0, amount - paid);
    const isOverdue = rr.due_date < todayStr && rr.status !== "paid";

    totalAmount += amount;
    totalPaid += paid;
    totalRemaining += remaining;
    if (rr.status !== "paid") countOpen++;
    if (isOverdue) countOverdue++;

    return {
      ...mapPayable({
        ...rr,
        supplier_name: rr.suppliers?.name ?? null,
      }),
      poNo: poMap.get(rr.purchase_order_id ?? "") ?? null,
      remaining,
    };
  });

  return {
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    canWrite: base.canWrite,
    payables,
    summary: { totalAmount, totalPaid, totalRemaining, countOpen, countOverdue },
  };
}

export async function getPayableDetail(id: string): Promise<PayableDetail | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();

  const { data: payable, error } = await supabase
    .from("payables")
    .select(
      "id, tenant_id, outlet_id, supplier_id, purchase_order_id, client_uuid, amount, total_paid, due_date, status, created_at, suppliers(name), purchase_orders(po_no)"
    )
    .eq("tenant_id", base.tenantId)
    .eq("id", id)
    .maybeSingle();

  if (error || !payable) return null;

  const { data: payments } = await supabase
    .from("payable_payments")
    .select("id, payable_id, client_uuid, amount, method, reference, paid_at, created_at")
    .eq("tenant_id", base.tenantId)
    .eq("payable_id", id)
    .order("paid_at", { ascending: true });

  const r = payable as unknown as {
    id: string;
    tenant_id: string;
    outlet_id: string;
    supplier_id: string;
    purchase_order_id: string | null;
    client_uuid: string;
    amount: number | string;
    total_paid: number | string;
    due_date: string;
    status: string;
    created_at: string;
    suppliers: { name: string | null } | null;
    purchase_orders: { po_no: string | null } | null;
  };

  const main: PayableRow = mapPayable({
    ...r,
    supplier_name: r.suppliers?.name ?? null,
  });
  main.poNo = r.purchase_orders?.po_no ?? null;

  const paymentRows: PayablePaymentRow[] = (payments ?? []).map((p) => ({
    id: p.id,
    payableId: p.payable_id,
    clientUuid: p.client_uuid,
    amount: Number(p.amount),
    method: p.method,
    reference: p.reference,
    paidAt: p.paid_at,
    createdAt: p.created_at,
  }));

  return { ...main, payments: paymentRows };
}
