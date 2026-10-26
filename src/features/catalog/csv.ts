export type ParsedProductRow = {
  line: number;
  name: string;
  sku: string;
  barcode: string;
  categoryName: string;
  unitName: string;
  sellPrice: string;
  minStock: string;
  kind: string;
};

export type CsvParseResult = {
  rows: ParsedProductRow[];
  error: string | null;
};

export const PRODUCT_CSV_HEADERS = [
  "nama",
  "sku",
  "barcode",
  "kategori",
  "satuan",
  "harga_jual",
  "stok_minimum",
  "jenis",
] as const;

/** Parser CSV minimal: mendukung tanda kutip, koma di dalam kutip, dan CRLF. */
export function parseCsv(input: string): string[][] {
  const text = input.replace(/^\uFEFF/, "");
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];

    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
      continue;
    }

    if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      row.push(field);
      field = "";
    } else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i += 1;
      row.push(field);
      field = "";
      if (row.some((value) => value.trim() !== "")) {
        rows.push(row);
      }
      row = [];
    } else {
      field += ch;
    }
  }

  row.push(field);
  if (row.some((value) => value.trim() !== "")) {
    rows.push(row);
  }

  return rows;
}

export function parseProductCsv(input: string): CsvParseResult {
  const table = parseCsv(input);

  if (table.length === 0) {
    return { rows: [], error: "File CSV kosong." };
  }

  const header = table[0].map((value) => value.trim().toLowerCase());
  const index = {
    name: header.indexOf("nama"),
    sku: header.indexOf("sku"),
    barcode: header.indexOf("barcode"),
    category: header.indexOf("kategori"),
    unit: header.indexOf("satuan"),
    sellPrice: header.indexOf("harga_jual"),
    minStock: header.indexOf("stok_minimum"),
    kind: header.indexOf("jenis"),
  };

  if (index.name < 0 || index.unit < 0 || index.sellPrice < 0) {
    return {
      rows: [],
      error:
        "Header wajib tidak ditemukan. Gunakan: nama, sku, barcode, kategori, satuan, harga_jual, stok_minimum, jenis.",
    };
  }

  const value = (cells: string[], at: number) =>
    at >= 0 ? (cells[at] ?? "").trim() : "";

  const rows = table.slice(1).map((cells, i) => ({
    line: i + 2,
    name: value(cells, index.name),
    sku: value(cells, index.sku),
    barcode: value(cells, index.barcode),
    categoryName: value(cells, index.category),
    unitName: value(cells, index.unit),
    sellPrice: value(cells, index.sellPrice),
    minStock: value(cells, index.minStock) || "0",
    kind: value(cells, index.kind) || "barang",
  }));

  return { rows, error: null };
}
