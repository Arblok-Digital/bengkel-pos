"use server";

import { revalidatePath } from "next/cache";

import { parseRupiah } from "@/lib/money";
import { createClient } from "@/lib/supabase/server";
import { parseProductCsv } from "./csv";

export type ImportPreviewRow = {
  line: number;
  name: string;
  sku: string;
  barcode: string;
  categoryName: string;
  unitName: string;
  sellPrice: number;
  minStock: number;
  kind: string;
};

export type ImportPreview = {
  total: number;
  validCount: number;
  errorCount: number;
  rows: ImportPreviewRow[];
  errors: { line: number; message: string }[];
};

export type ImportResult = { error: string | null; imported: number };

type InsertRow = {
  tenant_id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  category_id: string | null;
  base_unit_id: string;
  kind: string;
  track_stock: boolean;
  sell_price: number;
  min_stock: number;
  active: boolean;
};

type Context =
  | {
      ok: true;
      supabase: Awaited<ReturnType<typeof createClient>>;
      units: Map<string, string>;
      categories: Map<string, string>;
    }
  | { ok: false; error: string };

async function getImportContext(tenantId: string): Promise<Context> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { ok: false, error: "Sesi tidak valid. Login ulang." };

  const { data: membership } = await supabase
    .from("memberships")
    .select("role")
    .eq("tenant_id", tenantId)
    .eq("user_id", user.id)
    .eq("active", true)
    .maybeSingle();

  if (!membership || !["owner", "admin"].includes(membership.role)) {
    return { ok: false, error: "Anda tidak berhak mengimpor produk." };
  }

  const [unitsRes, categoriesRes] = await Promise.all([
    supabase.from("units").select("id, name").eq("tenant_id", tenantId),
    supabase.from("categories").select("id, name").eq("tenant_id", tenantId),
  ]);

  return {
    ok: true,
    supabase,
    units: new Map(
      (unitsRes.data ?? []).map((u) => [u.name.trim().toLowerCase(), u.id])
    ),
    categories: new Map(
      (categoriesRes.data ?? []).map((c) => [
        c.name.trim().toLowerCase(),
        c.id,
      ])
    ),
  };
}

async function buildRows(
  tenantId: string,
  csv: string
): Promise<
  | { ok: false; error: string }
  | {
      ok: true;
      rows: InsertRow[];
      preview: ImportPreviewRow[];
      errors: { line: number; message: string }[];
      total: number;
    }
> {
  const ctx = await getImportContext(tenantId);
  if (!ctx.ok) return { ok: false, error: ctx.error };

  const parsed = parseProductCsv(csv);
  if (parsed.error) return { ok: false, error: parsed.error };

  if (parsed.rows.length === 0) {
    return { ok: false, error: "File CSV tidak berisi baris produk." };
  }
  if (parsed.rows.length > 1000) {
    return { ok: false, error: "Maksimal 1000 baris per impor." };
  }

  const { data: existing } = await ctx.supabase
    .from("products")
    .select("sku, barcode")
    .eq("tenant_id", tenantId);

  const existingSkus = new Set(
    (existing ?? [])
      .map((p) => p.sku?.trim().toLowerCase())
      .filter((v): v is string => Boolean(v))
  );
  const existingBarcodes = new Set(
    (existing ?? [])
      .map((p) => p.barcode?.trim().toLowerCase())
      .filter((v): v is string => Boolean(v))
  );
  const seenSkus = new Set<string>();
  const seenBarcodes = new Set<string>();

  const rows: InsertRow[] = [];
  const preview: ImportPreviewRow[] = [];
  const errors: { line: number; message: string }[] = [];

  for (const raw of parsed.rows) {
    const fail = (message: string) =>
      errors.push({ line: raw.line, message });

    if (!raw.name) {
      fail("Nama produk kosong");
      continue;
    }

    const unitId = ctx.units.get(raw.unitName.trim().toLowerCase());
    if (!raw.unitName) {
      fail("Satuan kosong");
      continue;
    }
    if (!unitId) {
      fail(`Satuan "${raw.unitName}" tidak ditemukan`);
      continue;
    }

    let categoryId: string | null = null;
    if (raw.categoryName) {
      categoryId =
        ctx.categories.get(raw.categoryName.trim().toLowerCase()) ?? null;
      if (!categoryId) {
        fail(`Kategori "${raw.categoryName}" tidak ditemukan`);
        continue;
      }
    }

    let sellPrice: number;
    try {
      sellPrice = parseRupiah(raw.sellPrice);
    } catch {
      fail(`Harga jual tidak valid: "${raw.sellPrice}"`);
      continue;
    }
    if (sellPrice < 0) {
      fail("Harga jual tidak boleh negatif");
      continue;
    }

    const minStockText = raw.minStock.replace(",", ".");
    const minStock = Number(minStockText || "0");
    if (!Number.isFinite(minStock) || minStock < 0) {
      fail(`Stok minimum tidak valid: "${raw.minStock}"`);
      continue;
    }

    const kind = raw.kind.trim().toLowerCase() || "barang";
    if (!["barang", "jasa", "paket"].includes(kind)) {
      fail(`Jenis produk tidak valid: "${raw.kind}"`);
      continue;
    }

    const sku = raw.sku.trim();
    const barcode = raw.barcode.trim();
    if (sku) {
      const key = sku.toLowerCase();
      if (seenSkus.has(key)) {
        fail(`SKU "${sku}" duplikat di file`);
        continue;
      }
      if (existingSkus.has(key)) {
        fail(`SKU "${sku}" sudah ada di database`);
        continue;
      }
      seenSkus.add(key);
    }
    if (barcode) {
      const key = barcode.toLowerCase();
      if (seenBarcodes.has(key)) {
        fail(`Barcode "${barcode}" duplikat di file`);
        continue;
      }
      if (existingBarcodes.has(key)) {
        fail(`Barcode "${barcode}" sudah ada di database`);
        continue;
      }
      seenBarcodes.add(key);
    }

    rows.push({
      tenant_id: tenantId,
      name: raw.name,
      sku: sku || null,
      barcode: barcode || null,
      category_id: categoryId,
      base_unit_id: unitId,
      kind,
      track_stock: kind === "barang",
      sell_price: sellPrice,
      min_stock: minStock,
      active: true,
    });

    preview.push({
      line: raw.line,
      name: raw.name,
      sku,
      barcode,
      categoryName: raw.categoryName,
      unitName: raw.unitName,
      sellPrice,
      minStock,
      kind,
    });
  }

  return {
    ok: true,
    rows,
    preview,
    errors,
    total: parsed.rows.length,
  };
}

export async function previewProductsCsvAction(
  tenantId: string,
  csv: string
): Promise<{ preview?: ImportPreview; error?: string }> {
  const built = await buildRows(tenantId, csv);
  if (!built.ok) return { error: built.error };

  return {
    preview: {
      total: built.total,
      validCount: built.rows.length,
      errorCount: built.errors.length,
      rows: built.preview,
      errors: built.errors,
    },
  };
}

export async function importProductsCsvAction(
  tenantId: string,
  csv: string
): Promise<ImportResult> {
  const built = await buildRows(tenantId, csv);
  if (!built.ok) return { error: built.error, imported: 0 };

  if (built.errors.length > 0) {
    return {
      error: `Masih ada ${built.errors.length} baris bermasalah. Perbaiki lalu pratinjau ulang.`,
      imported: 0,
    };
  }
  if (built.rows.length === 0) {
    return { error: "Tidak ada baris valid untuk diimpor.", imported: 0 };
  }

  const ctx = await getImportContext(tenantId);
  if (!ctx.ok) return { error: ctx.error, imported: 0 };

  const { error } = await ctx.supabase.from("products").insert(built.rows);

  if (error) {
    if (error.code === "23505") {
      return {
        error: "SKU/barcode bentrok dengan produk lain. Pratinjau ulang.",
        imported: 0,
      };
    }
    return { error: "Gagal mengimpor produk.", imported: 0 };
  }

  revalidatePath("/produk");
  return { error: null, imported: built.rows.length };
}
