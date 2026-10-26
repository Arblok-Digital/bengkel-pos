import { describe, expect, it } from "vitest";

import { formatRupiah, mulQty, parseRupiah } from "@/lib/money";

describe("formatRupiah", () => {
  it("nol", () => {
    expect(formatRupiah(0)).toBe("Rp 0");
  });

  it("ribuan", () => {
    expect(formatRupiah(1250000)).toBe("Rp 1.250.000");
  });

  it("satuan", () => {
    expect(formatRupiah(1)).toBe("Rp 1");
  });

  it("negatif", () => {
    expect(formatRupiah(-5000)).toBe("-Rp 5.000");
  });

  it("angka besar", () => {
    expect(formatRupiah(999999999999)).toBe("Rp 999.999.999.999");
  });

  it("menolak non-integer", () => {
    expect(() => formatRupiah(100.5)).toThrow();
  });

  it("menolak NaN dan Infinity", () => {
    expect(() => formatRupiah(NaN)).toThrow();
    expect(() => formatRupiah(Infinity)).toThrow();
  });
});

describe("parseRupiah", () => {
  it("dengan simbol Rp dan titik ribuan", () => {
    expect(parseRupiah("Rp 1.250.000")).toBe(1250000);
  });

  it("tanpa simbol", () => {
    expect(parseRupiah("1.250.000")).toBe(1250000);
  });

  it("tanpa pemisah", () => {
    expect(parseRupiah("1250000")).toBe(1250000);
  });

  it("negatif", () => {
    expect(parseRupiah("-Rp 5.000")).toBe(-5000);
  });

  it("desimal koma dibulatkan", () => {
    expect(parseRupiah("Rp 1.250.000,50")).toBe(1250001);
  });

  it("nol", () => {
    expect(parseRupiah("Rp 0")).toBe(0);
  });

  it("menolak string kosong", () => {
    expect(() => parseRupiah("")).toThrow();
  });

  it("menolak teks bukan angka", () => {
    expect(() => parseRupiah("abc")).toThrow();
  });

  it("menolak non-string", () => {
    expect(() => parseRupiah(123 as unknown as string)).toThrow();
  });
});

describe("mulQty", () => {
  it("setengah sak", () => {
    expect(mulQty(0.5, 10000)).toBe(5000);
  });

  it("desimal 2,5", () => {
    expect(mulQty(2.5, 10000)).toBe(25000);
  });

  it("qty nol", () => {
    expect(mulQty(0, 10000)).toBe(0);
  });

  it("harga nol", () => {
    expect(mulQty(3, 0)).toBe(0);
  });

  it("qty negatif", () => {
    expect(mulQty(-0.5, 10000)).toBe(-5000);
  });

  it("menghindari artefak float (0,3 x 100)", () => {
    expect(mulQty(0.3, 100)).toBe(30);
  });

  it("pembulatan setengah menjauhi nol", () => {
    expect(mulQty(1.5, 3)).toBe(5);
    expect(mulQty(-1.5, 3)).toBe(-5);
  });

  it("menerima qty string", () => {
    expect(mulQty("0.5", 10000)).toBe(5000);
  });

  it("menolak harga non-integer", () => {
    expect(() => mulQty(1, 100.5)).toThrow();
  });

  it("menolak qty bukan angka", () => {
    expect(() => mulQty(NaN, 100)).toThrow();
    expect(() => mulQty(Infinity, 100)).toThrow();
  });

  it("round-trip format/parse", () => {
    const n = 1234567;
    expect(parseRupiah(formatRupiah(n))).toBe(n);
  });

  it("angka besar tidak overflow safe integer (format)", () => {
    expect(formatRupiah(9007199254740991)).toContain("Rp");
  });
});
