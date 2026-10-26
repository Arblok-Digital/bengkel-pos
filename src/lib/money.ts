// Uang: integer rupiah (number bulat) di TS, bigint di DB.
// Semua format/hitung uang WAJIB lewat file ini (AGENTS.md Bagian 3).
// Dilarang float, dilarang toFixed untuk menghitung.

const RUPIAH_SYMBOL = "Rp";

function assertFiniteNumber(value: unknown, name: string): asserts value is number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`${name} harus berupa angka finite`);
  }
}

function assertIntegerRupiah(value: number, name: string): void {
  if (!Number.isInteger(value)) {
    throw new TypeError(`${name} harus integer rupiah (tanpa desimal)`);
  }
  if (!Number.isSafeInteger(value)) {
    throw new RangeError(`${name} di luar safe integer`);
  }
}

/** Format angka integer rupiah ke "Rp 1.250.000" (negatif: "-Rp 5.000"). */
export function formatRupiah(value: number): string {
  assertFiniteNumber(value, "value");
  assertIntegerRupiah(value, "value");

  const negative = value < 0;
  const digits = String(Math.abs(value));
  const withThousands = digits.replace(/\B(?=(\d{3})+(?!\d))/g, ".");

  return `${negative ? "-" : ""}${RUPIAH_SYMBOL} ${withThousands}`;
}

/** Parse string rupiah ke integer rupiah. Menerima "Rp 1.250.000", "1.250.000",
 *  "1250000", "-Rp 5.000", "Rp 1.250.000,50" (dibulatkan). */
export function parseRupiah(input: string): number {
  if (typeof input !== "string") {
    throw new TypeError("input harus string");
  }

  let s = input.trim().replace(/rp/i, "").trim();
  if (s === "") {
    throw new Error("input rupiah kosong");
  }

  const negative = s.startsWith("-");
  if (negative) s = s.slice(1).trim();

  // Ada koma desimal (format Indonesia): titik = ribuan, koma = desimal.
  if (s.includes(",")) {
    s = s.replace(/\./g, "").replace(",", ".");
    const n = Number(s);
    if (!Number.isFinite(n)) {
      throw new Error("format rupiah tidak valid");
    }
    const rounded = Math.sign(n) * (Math.floor(Math.abs(n) + 0.5));
    return negative ? -Math.abs(rounded) : Math.abs(rounded);
  }

  // Tanpa koma: buang semua titik (ribuan) dan spasi.
  s = s.replace(/\./g, "").replace(/\s/g, "");
  if (!/^\d+$/.test(s)) {
    throw new Error("format rupiah tidak valid");
  }

  const n = Number(s);
  if (!Number.isSafeInteger(n)) {
    throw new RangeError("angka rupiah terlalu besar");
  }
  return negative ? -n : n;
}

/** Hitung qty (boleh desimal, mis. 0.5 sak) × harga (integer rupiah) → integer rupiah.
 *  Pembulatan: setengah menjauhi nol. */
export function mulQty(qty: number | string, price: number): number {
  let q: number;
  if (typeof qty === "string") {
    q = Number(qty);
    if (!Number.isFinite(q)) {
      throw new TypeError("qty harus angka finite");
    }
  } else if (typeof qty === "number") {
    q = qty;
    assertFiniteNumber(q, "qty");
  } else {
    throw new TypeError("qty harus number atau string angka");
  }

  assertFiniteNumber(price, "price");
  assertIntegerRupiah(price, "price");

  const exact = q * price;
  if (!Number.isFinite(exact)) {
    throw new RangeError("hasil perkalian tidak finite");
  }

  // Bulatkan setengah menjauhi nol (hindari artefak float dengan epsilon kecil).
  const scaled = exact >= 0 ? exact + 1e-9 : exact - 1e-9;
  return Math.sign(scaled) * Math.floor(Math.abs(scaled) + 0.5);
}
