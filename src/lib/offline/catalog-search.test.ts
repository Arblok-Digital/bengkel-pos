import { describe, expect, it } from "vitest";

import { normalizeSearch, searchProducts } from "./catalog-search";

const products = [
  { name: "Oli Mesin 1L", sku: "OLI-1L", barcode: "8999001" },
  { name: "Semen 40kg", sku: "SEMEN-1", barcode: "8999002" },
  { name: "Oli Gardan", sku: "OLI-GDN", barcode: "8999010" },
  { name: "Café Filter", sku: null, barcode: null },
];

describe("normalizeSearch", () => {
  it("menghapus spasi berlebih, huruf besar, dan diakritik", () => {
    expect(normalizeSearch("  OLI   Mesin ")).toBe("oli mesin");
    expect(normalizeSearch("Café")).toBe("cafe");
  });
});

describe("searchProducts", () => {
  it("mencari dari nama tanpa peduli huruf besar/kecil", () => {
    expect(searchProducts(products, "oli").map((row) => row.name)).toEqual([
      "Oli Gardan",
      "Oli Mesin 1L",
    ]);
  });

  it("mencari dari SKU, termasuk tanpa tanda hubung", () => {
    expect(searchProducts(products, "oli-1l")[0]?.name).toBe("Oli Mesin 1L");
    expect(searchProducts(products, "oli1l")[0]?.name).toBe("Oli Mesin 1L");
  });

  it("mencari dari barcode (hasil scan)", () => {
    expect(searchProducts(products, "8999002")).toEqual([products[1]]);
  });

  it("multi-kata harus cocok semua", () => {
    expect(searchProducts(products, "oli 1l")[0]?.name).toBe("Oli Mesin 1L");
    expect(searchProducts(products, "oli 40kg")).toEqual([]);
  });

  it("mendahulukan exact barcode/SKU", () => {
    const rows = [
      { name: "Produk Oli", sku: "X-1", barcode: "123" },
      { name: "Lain", sku: "123", barcode: null },
    ];
    expect(searchProducts(rows, "123")[0]?.name).toBe("Lain");
  });

  it("query kosong mengembalikan semua, terurut nama", () => {
    expect(searchProducts(products, "   ").map((row) => row.name)).toEqual([
      "Café Filter",
      "Oli Gardan",
      "Oli Mesin 1L",
      "Semen 40kg",
    ]);
  });

  it("tidak menemukan apa pun untuk kata yang tidak ada", () => {
    expect(searchProducts(products, "tidak-ada")).toEqual([]);
  });
});
