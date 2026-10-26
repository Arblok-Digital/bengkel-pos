import { createClient } from "@/lib/supabase/server";

export type CatalogItem = {
  id: string;
  name: string;
};

export type CatalogData = {
  tenantId: string;
  tenantName: string;
  role: string;
  canWrite: boolean;
  categories: CatalogItem[];
  units: CatalogItem[];
};

/** Katalog tenant utama (membership aktif pertama). */
export async function getCatalog(): Promise<CatalogData | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: memberships, error } = await supabase
    .from("memberships")
    .select("tenant_id, role, tenants(id, name)")
    .eq("user_id", user.id)
    .eq("active", true)
    .limit(1);

  if (error || !memberships || memberships.length === 0) return null;

  const membership = memberships[0];
  const tenant = Array.isArray(membership.tenants)
    ? membership.tenants[0]
    : membership.tenants;

  if (!tenant) return null;

  const [{ data: categories }, { data: units }] = await Promise.all([
    supabase
      .from("categories")
      .select("id, name")
      .eq("tenant_id", membership.tenant_id)
      .order("name"),
    supabase
      .from("units")
      .select("id, name")
      .eq("tenant_id", membership.tenant_id)
      .order("name"),
  ]);

  return {
    tenantId: membership.tenant_id,
    tenantName: tenant.name,
    role: membership.role,
    canWrite: ["owner", "admin"].includes(membership.role),
    categories: categories ?? [],
    units: units ?? [],
  };
}

export type ProductRow = {
  id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  categoryId: string | null;
  categoryName: string | null;
  baseUnitId: string | null;
  unitName: string | null;
  kind: string;
  sellPrice: number;
  minStock: number;
  active: boolean;
};

type RawProduct = {
  id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  category_id: string | null;
  base_unit_id: string | null;
  kind: string;
  sell_price: number;
  min_stock: number;
  active: boolean;
};

const PRODUCT_COLUMNS =
  "id, name, sku, barcode, category_id, base_unit_id, kind, sell_price, min_stock, active";

function toProductRow(
  raw: RawProduct,
  categoryNames: Map<string, string>,
  unitNames: Map<string, string>
): ProductRow {
  return {
    id: raw.id,
    name: raw.name,
    sku: raw.sku,
    barcode: raw.barcode,
    categoryId: raw.category_id,
    categoryName: raw.category_id
      ? (categoryNames.get(raw.category_id) ?? null)
      : null,
    baseUnitId: raw.base_unit_id,
    unitName: raw.base_unit_id
      ? (unitNames.get(raw.base_unit_id) ?? null)
      : null,
    kind: raw.kind,
    sellPrice: raw.sell_price,
    minStock: Number(raw.min_stock),
    active: raw.active,
  };
}

export type CatalogWithProducts = CatalogData & { products: ProductRow[] };

export async function getProductsPage(): Promise<CatalogWithProducts | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("products")
    .select(PRODUCT_COLUMNS)
    .eq("tenant_id", base.tenantId)
    .order("name");

  const categoryNames = new Map(base.categories.map((c) => [c.id, c.name]));
  const unitNames = new Map(base.units.map((u) => [u.id, u.name]));

  return {
    ...base,
    products: (data ?? []).map((raw) =>
      toProductRow(raw as RawProduct, categoryNames, unitNames)
    ),
  };
}

export type ProductEditData = CatalogData & { product: ProductRow };

export async function getProductForEdit(
  id: string
): Promise<ProductEditData | null> {
  const base = await getCatalog();
  if (!base) return null;

  const supabase = await createClient();
  const { data } = await supabase
    .from("products")
    .select(PRODUCT_COLUMNS)
    .eq("tenant_id", base.tenantId)
    .eq("id", id)
    .maybeSingle();

  if (!data) return null;

  const categoryNames = new Map(base.categories.map((c) => [c.id, c.name]));
  const unitNames = new Map(base.units.map((u) => [u.id, u.name]));

  return {
    ...base,
    product: toProductRow(data as RawProduct, categoryNames, unitNames),
  };
}
