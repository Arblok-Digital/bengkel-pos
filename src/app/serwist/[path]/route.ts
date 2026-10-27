import { createSerwistRoute } from "@serwist/turbopack";

// Menyajikan /serwist/sw.js dari src/app/sw.ts (Turbopack).
// Halaman offline TIDAK didaftarkan di sini karena `@serwist/turbopack`
// mengosongkan daftar precache saat `next dev`; service worker menyimpannya
// sendiri lewat event `install` (lihat src/app/sw.ts).
export const { dynamic, dynamicParams, revalidate, generateStaticParams, GET } =
  createSerwistRoute({
    swSrc: "src/app/sw.ts",
    useNativeEsbuild: true,
  });
