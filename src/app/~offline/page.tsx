import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Tidak ada koneksi",
};

// Halaman cadangan saat jaringan mati (dipanggil service worker).
// Sengaja statis dan tanpa data: harus tetap bisa tampil tanpa server.
export const dynamic = "force-static";

export default function OfflinePage() {
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-bold">Tidak ada koneksi internet</h1>
      <p className="text-muted-foreground text-sm">
        Halaman ini tidak tersimpan di perangkat. Sambungkan kembali internet
        lalu coba lagi.
      </p>
      <p className="text-sm">
        Transaksi yang sudah tersimpan di perangkat akan dikirim otomatis
        setelah koneksi pulih.
      </p>
      <Link
        href="/kasir"
        className="inline-flex h-11 items-center justify-center rounded-md border border-input px-4 text-sm hover:bg-accent"
      >
        Coba buka kasir lagi
      </Link>
    </main>
  );
}
