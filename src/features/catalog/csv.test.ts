import { describe, expect, it } from "vitest";

import { parseCsv, parseProductCsv } from "@/features/catalog/csv";

const header = "nama,sku,barcode,kategori,satuan,harga_jual,stok_minimum,jenis";

describe("parseCsv", () => {
  it("memisahkan baris dan kolom", () => {
    expect(parseCsv("a,b\n1,2")).toEqual([
      ["a", "b"],
      ["1", "2"],
    ]);
  });

  it("mendukung koma di dalam kutip", () => {
    expect(parseCsv('a,b\n"Oli, 1L",2')).toEqual([
      ["a", "b"],
      ["Oli, 1L", "2"],
    ]);
  });

  it("mendukung CRLF dan BOM", () => {
    expect(parseCsv("\uFEFFa,b\r\n1,2\r\n")).toEqual([
      ["a", "b"],
      ["1", "2"],
    ]);
  });

  it("mengabaikan baris kosong", () => {
    expect(parseCsv("a,b\n\n1,2\n")).toEqual([
      ["a", "b"],
      ["1", "2"],
    ]);
  });
});

describe("parseProductCsv", () => {
  it("memetakan header produk", () => {
    const result = parseProductCsv(
      `${header}\nOli Mesin,OLI-1,899,Oli,liter,50000,2,barang`
    );

    expect(result.error).toBeNull();
    expect(result.rows).toHaveLength(1);
    expect(result.rows[0]).toMatchObject({
      line: 2,
      name: "Oli Mesin",
      sku: "OLI-1",
      barcode: "899",
      categoryName: "Oli",
      unitName: "liter",
      sellPrice: "50000",
      minStock: "2",
      kind: "barang",
    });
  });

  it("memberi default stok 0 dan jenis barang", () => {
    const result = parseProductCsv(`${header}\nOli,,, ,liter,50000,,`);

    expect(result.error).toBeNull();
    expect(result.rows[0].minStock).toBe("0");
    expect(result.rows[0].kind).toBe("barang");
  });

  it("menolak header wajib yang hilang", () => {
    const result = parseProductCsv("nama,satuan\nOli,liter");
    expect(result.error).not.toBeNull();
    expect(result.rows).toHaveLength(0);
  });

  it("menolak file kosong", () => {
    expect(parseProductCsv("").error).not.toBeNull();
  });
});
