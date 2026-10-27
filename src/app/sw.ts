/// <reference lib="esnext" />
/// <reference lib="webworker" />

// Service worker (Serwist) untuk aplikasi kasir.
//
// Prinsip keamanan: HTML halaman ber-auntentikasi TIDAK disimpan di cache.
// Yang di-cache hanya aset statis (/_next/static, ikon) dan halaman offline,
// supaya perangkat yang dipakai bergantian tidak menyajikan data pengguna lain.
//
// Catatan: fallback offline sengaja TIDAK memakai opsi `fallbacks` Serwist.
// `@serwist/turbopack` mematikan precache manifest saat `next dev`
// (`disablePrecacheManifest`), sehingga `PrecacheFallbackPlugin` tidak akan
// menemukan apa pun di mode dev. Handler di bawah bekerja sama di dev dan
// produksi, dan tetap tidak menyimpan HTML halaman lain.
//
// Cache katalog offline (Dexie) dikelola di src/lib/offline; service worker
// sengaja tidak menyimpan HTML/response API ber-auntentikasi.

import type { PrecacheEntry, RouteHandlerCallback, SerwistGlobalConfig } from "serwist";
import { CacheFirst, Serwist, StaleWhileRevalidate } from "serwist";

declare global {
  interface WorkerGlobalScope extends SerwistGlobalConfig {
    __SW_MANIFEST: (PrecacheEntry | string)[] | undefined;
  }
}

declare const self: ServiceWorkerGlobalScope;

const OFFLINE_URL = new URL("/~offline", self.location.origin).href;
const OFFLINE_CACHE = "halaman-offline";

// HTML darurat: dipakai kalau halaman /~offline belum sempat tersimpan.
// Ditulis inline supaya tidak butuh jaringan maupun aset lain.
const OFFLINE_FALLBACK_HTML = `<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Tidak ada koneksi</title>
</head>
<body style="margin:0;font-family:system-ui,sans-serif;background:#0f172a;color:#f8fafc">
<main style="max-width:28rem;margin:0 auto;padding:1.5rem;min-height:100dvh;display:flex;flex-direction:column;justify-content:center;gap:1rem">
<h1 style="margin:0;font-size:1.5rem">Tidak ada koneksi internet</h1>
<p style="margin:0;color:#cbd5e1;font-size:.875rem">Halaman ini tidak tersimpan di perangkat. Sambungkan kembali internet lalu coba lagi.</p>
<p style="margin:0;font-size:.875rem">Transaksi yang sudah tersimpan di perangkat akan dikirim otomatis setelah koneksi pulih.</p>
</main>
</body>
</html>`;

async function halamanOffline(): Promise<Response> {
  const cache = await caches.open(OFFLINE_CACHE);
  const tersimpan = await cache.match(OFFLINE_URL);
  if (tersimpan) return tersimpan;

  try {
    const response = await fetch(OFFLINE_URL, { cache: "reload" });
    if (response.ok) {
      await cache.put(OFFLINE_URL, response.clone());
      return response;
    }
  } catch {
    // Jaringan mati: lanjut ke HTML darurat.
  }

  return new Response(OFFLINE_FALLBACK_HTML, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      // Jangan sampai HTML darurat ikut tersimpan oleh lapisan cache lain.
      "Cache-Control": "no-store",
    },
  });
}

// Simpan halaman offline saat service worker dipasang, supaya bisa dibuka
// tanpa jaringan. Gagal menyimpan tidak boleh menggagalkan instalasi.
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(OFFLINE_CACHE)
      .then((cache) => cache.add(new Request(OFFLINE_URL, { cache: "reload" })))
      .catch(() => undefined)
  );
});

const tanganiNavigasi: RouteHandlerCallback = async ({ request }) => {
  try {
    return await fetch(request);
  } catch {
    return halamanOffline();
  }
};

const serwist = new Serwist({
  precacheEntries: self.__SW_MANIFEST,
  skipWaiting: true,
  clientsClaim: true,
  // Tidak dipakai: handler navigasi memakai `fetch(request)` sendiri, jadi
  // preload hanya akan menggandakan request ke jaringan.
  navigationPreload: false,
  runtimeCaching: [
    {
      // Navigasi selalu ke jaringan; saat gagal tampilkan halaman offline.
      matcher: ({ request }) => request.mode === "navigate",
      handler: tanganiNavigasi,
    },
    {
      // Bundle & CSS Next.js: nama file sudah ber-hash, aman di-cache lama.
      matcher: ({ url }) =>
        url.origin === self.location.origin &&
        url.pathname.startsWith("/_next/static/"),
      handler: new StaleWhileRevalidate({ cacheName: "aset-statis" }),
    },
    {
      // Ikon, logo struk, dan gambar lain dari origin sendiri.
      matcher: ({ request, url }) =>
        url.origin === self.location.origin && request.destination === "image",
      handler: new CacheFirst({ cacheName: "gambar" }),
    },
  ],
});

serwist.addEventListeners();
