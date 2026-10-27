import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    id: "/",
    name: "Kasir Bengkel & Toko Bangunan",
    short_name: "Kasir Bengkel",
    description:
      "Aplikasi kasir bengkel dan toko bangunan: shift, penjualan, pembayaran, stok, dan struk.",
    lang: "id",
    dir: "ltr",
    start_url: "/kasir",
    scope: "/",
    display: "standalone",
    orientation: "any",
    background_color: "#0f172a",
    theme_color: "#0f172a",
    categories: ["business", "productivity"],
    icons: [
      {
        src: "/icons/icon-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icons/icon-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icons/icon-maskable-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "maskable",
      },
      {
        src: "/icons/icon-maskable-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
    shortcuts: [
      { name: "Kasir", short_name: "Kasir", url: "/kasir" },
      { name: "Penjualan", short_name: "Penjualan", url: "/penjualan" },
      { name: "Stok menipis", short_name: "Stok", url: "/stok/menipis" },
    ],
  };
}
