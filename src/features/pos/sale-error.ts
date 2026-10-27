// Pesan error penjualan dari RPC Postgres.
// Dipisah dari actions.ts karena modul "use server" hanya boleh mengekspor
// fungsi async.

const KNOWN_FRAGMENTS = [
  "berhak",
  "Stok",
  "Harga",
  "Satuan",
  "Shift",
  "limit kredit",
  "Pembayaran",
  "Minimal",
  "client_uuid",
  "Pelanggan",
  "Outlet",
  "Produk",
  "Qty",
  "Diskon",
  "Metode",
];

/** Error jaringan bukan kesalahan data: transaksi layak masuk antrean offline. */
export function isNetworkError(message: string): boolean {
  return /failed to fetch|fetch failed|network|timeout|ECONNREFUSED|ENOTFOUND/i.test(
    message
  );
}

/** Teruskan pesan server yang dikenal, selain itu pakai pesan umum. */
export function saleErrorMessage(message: string, fallback: string): string {
  const known = KNOWN_FRAGMENTS.some((fragment) =>
    message.toLowerCase().includes(fragment.toLowerCase())
  );
  return known ? message : fallback;
}
