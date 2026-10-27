import { describe, expect, it } from "vitest";

import { mulQty } from "./money";
import { addQtyDecimal, mulQtyDecimal } from "./qty";

describe("mulQtyDecimal (konversi satuan ke stok base)", () => {
  it("mengubah 0,5 sak menjadi 25 kg", () => {
    expect(mulQtyDecimal(0.5, 50)).toBe(25);
  });

  it("mengubah 2,5 sak menjadi 125 kg", () => {
    expect(mulQtyDecimal(2.5, 50)).toBe(125);
  });

  it("tidak menghasilkan artefak float (0,1 x 3)", () => {
    expect(mulQtyDecimal(0.1, 3)).toBe(0.3);
    expect(mulQtyDecimal(1 / 3, 3)).toBe(1);
  });

  it("total rupiah tetap lewat money.ts", () => {
    expect(mulQty(2.5, 65000)).toBe(162500);
  });

  it("menolak qty negatif dan faktor nol", () => {
    expect(() => mulQtyDecimal(-1, 50)).toThrow(RangeError);
    expect(() => mulQtyDecimal(1, 0)).toThrow(RangeError);
  });
});

describe("addQtyDecimal (stok lokal setelah transaksi offline)", () => {
  it("mengurangi stok tanpa artefak float", () => {
    expect(addQtyDecimal(7, -0.5)).toBe(6.5);
    expect(addQtyDecimal(0.3, -0.1)).toBe(0.2);
  });

  it("menolak nilai bukan angka", () => {
    expect(() => addQtyDecimal(Number.NaN, 0)).toThrow(TypeError);
    expect(() => addQtyDecimal(1, Number.POSITIVE_INFINITY)).toThrow(TypeError);
  });
});
