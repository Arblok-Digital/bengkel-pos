import { describe, expect, it } from "vitest";

import { mulQty } from "./money";
import { mulQtyDecimal } from "./qty";

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
