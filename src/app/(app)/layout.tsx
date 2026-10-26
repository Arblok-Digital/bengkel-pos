import Link from "next/link";
import { redirect } from "next/navigation";

import { hasManagerRole } from "@/features/staff/queries";
import { createClient } from "@/lib/supabase/server";
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

  return (
    <div className="min-h-screen">
      <header className="flex items-center justify-between gap-4 border-b px-6 py-3">
        <span className="font-semibold">Kasir Bengkel &amp; Toko Bangunan</span>
        <div className="flex items-center gap-4 text-sm">
          <nav className="flex items-center gap-4">
            <Link href="/" className="hover:underline">
              Beranda
            </Link>
            <Link href="/katalog" className="hover:underline">
              Katalog
            </Link>
            <Link href="/produk" className="hover:underline">
              Produk
            </Link>
            <Link href="/pelanggan" className="hover:underline">
              Pelanggan
            </Link>
            <Link href="/pemasok" className="hover:underline">
              Pemasok
            </Link>
            {canManage ? (
              <Link href="/pengaturan" className="hover:underline">
                Pengaturan
              </Link>
            ) : null}
          </nav>
          <LogoutButton />
        </div>
      </header>
      <main className="p-6">{children}</main>
    </div>
  );
}
