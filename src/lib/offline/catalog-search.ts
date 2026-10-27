// Pencarian katalog dari data lokal. Fungsi murni supaya mudah diuji dan
// dipakai baik untuk hasil dari Dexie maupun fallback di memori.

export type SearchableProduct = {
  name: string;
  sku: string | null;
  barcode: string | null;
};

export function normalizeSearch(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

function compact(value: string): string {
  return normalizeSearch(value).replace(/[^a-z0-9]/g, "");
}

function scoreProduct(
  product: SearchableProduct,
  normalizedQuery: string,
  compactQuery: string
): number | null {
  const name = normalizeSearch(product.name);
  const sku = normalizeSearch(product.sku ?? "");
  const barcode = normalizeSearch(product.barcode ?? "");
  const compactSku = compact(product.sku ?? "");
  const compactBarcode = compact(product.barcode ?? "");

  const tokens = normalizedQuery.split(" ").filter(Boolean);
  const matchesTokens = tokens.every(
    (token) =>
      name.includes(token) ||
      sku.includes(token) ||
      barcode.includes(token) ||
      (token.length >= 3 &&
        (compactSku.includes(token) || compactBarcode.includes(token)))
  );

  if (!matchesTokens) return null;

  const compactMatches =
    compactQuery.length >= 3 &&
    (compactBarcode === compactQuery || compactSku === compactQuery);

  if (barcode === normalizedQuery || sku === normalizedQuery || compactMatches) {
    return 0;
  }
  if (name === normalizedQuery) return 1;
  if (name.startsWith(normalizedQuery)) return 2;
  return 3;
}

/**
 * Cari produk berdasarkan nama, SKU, atau barcode.
 * Multi-kata = semua kata harus cocok. Hasil exact SKU/barcode didahulukan.
 */
export function searchProducts<T extends SearchableProduct>(
  products: readonly T[],
  query: string
): T[] {
  const normalizedQuery = normalizeSearch(query);
  if (!normalizedQuery) {
    return [...products].sort((a, b) => a.name.localeCompare(b.name, "id"));
  }

  const compactQuery = compact(query);
  const scored: { product: T; score: number }[] = [];

  for (const product of products) {
    const score = scoreProduct(product, normalizedQuery, compactQuery);
    if (score !== null) scored.push({ product, score });
  }

  return scored
    .sort(
      (a, b) =>
        a.score - b.score || a.product.name.localeCompare(b.product.name, "id")
    )
    .map((row) => row.product);
}
