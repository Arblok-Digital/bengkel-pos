// Qty boleh desimal (mis. 0,5 sak). Jangan pakai matematika uang di sini:
// hasil konversi qty tetap qty, bukan rupiah.

const QTY_DECIMALS = 3;

/** Qty × faktor satuan → qty dalam satuan dasar, dibulatkan 3 desimal. */
export function mulQtyDecimal(qty: number, factor: number): number {
  if (typeof qty !== "number" || !Number.isFinite(qty)) {
    throw new TypeError("qty harus angka finite");
  }
  if (typeof factor !== "number" || !Number.isFinite(factor)) {
    throw new TypeError("factor harus angka finite");
  }
  if (qty < 0 || factor <= 0) {
    throw new RangeError("qty tidak boleh negatif dan factor harus lebih dari 0");
  }

  const scale = 10 ** QTY_DECIMALS;
  const exact = qty * factor;
  const scaled = exact >= 0 ? exact + 1e-9 : exact - 1e-9;
  return Math.round(scaled * scale) / scale;
}
