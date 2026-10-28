import Link from "next/link";
import { redirect } from "next/navigation";

import { hasManagerRole } from "@/features/staff/queries";
import { createClient } from "@/lib/supabase/server";
import { getWorkspace } from "@/features/tenant/workspace";
import { LogoutButton } from "./logout-button";

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const canManage = await hasManagerRole();
  const workspace = await getWorkspace();

  return (
    <div className="min-h-screen">
      <header className="flex items-center justify-between gap-4 border-b px-6 py-3 print:hidden">
        <span className="font-semibold">Kasir Bengkel &amp; Toko Bangunan</span>
        <div className="flex items-center gap-4 text-sm">
          <nav className="flex items-center gap-4">
            <Link href="/" className="hover:underline">
              Beranda
            </Link>
            <Link href="/kasir" className="hover:underline">
              Kasir
            </Link>
            <Link href="/penjualan" className="hover:underline">
              Penjualan
            </Link>
            <Link href="/piutang" className="hover:underline">
              Piutang
            </Link>
            <Link href="/katalog" className="hover:underline">
              Katalog
            </Link>
            <Link href="/produk" className="hover:underline">
              Produk
            </Link>
            <Link href="/stok" className="hover:underline">
              Stok
            </Link>
            <Link href="/pelanggan" className="hover:underline">
              Pelanggan
            </Link>
            <Link href="/pemasok" className="hover:underline">
              Pemasok
            </Link>
            <Link href="/pembelian" className="hover:underline">
              Pembelian
            </Link>
            <Link href="/penerimaan" className="hover:underline">
              Penerimaan
            </Link>
            <Link href="/hutang" className="hover:underline">
              Hutang
            </Link>
            {canManage ? (
              <Link href="/pengaturan" className="hover:underline">
                Pengaturan
              </Link>
            ) : null}
            {workspace?.mode === "bengkel" ? (
              <Link href="/bengkel" className="hover:underline">
                Bengkel
              </Link>
            ) : null}
            {workspace?.mode === "toko" ? (
              <Link href="/toko" className="hover:underline">
                Toko Bangunan
              </Link>
            ) : null}
          </nav>
          {workspace ? (
            <Link href="/pilih-usaha" className="rounded border px-2 py-1 text-xs">
              {workspace.tenantName} · {workspace.mode === "bengkel" ? "Bengkel" : "Toko"}
            </Link>
          ) : null}
          <LogoutButton />
        </div>
      </header>
      <main className="p-6 print:p-0">{children}</main>
    </div>
  );
}
