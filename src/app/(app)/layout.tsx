import Link from "next/link";
import { redirect } from "next/navigation";
import {
  Boxes,
  CarFront,
  ClipboardList,
  HandCoins,
  LayoutDashboard,
  PackageSearch,
  ReceiptText,
  Settings,
  ShoppingCart,
  Store,
  Tags,
  Truck,
  UsersRound,
  Wrench,
} from "lucide-react";

import { hasManagerRole } from "@/features/staff/queries";
import { createClient } from "@/lib/supabase/server";
import { getWorkspace } from "@/features/tenant/workspace";
import { LogoutButton } from "./logout-button";

type NavItem = {
  href: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
};

const sharedOperations: NavItem[] = [
  { href: "/kasir", label: "Kasir", icon: ShoppingCart },
  { href: "/penjualan", label: "Penjualan", icon: ReceiptText },
  { href: "/piutang", label: "Piutang", icon: HandCoins },
];

const inventoryItems: NavItem[] = [
  { href: "/produk", label: "Produk", icon: PackageSearch },
  { href: "/katalog", label: "Katalog", icon: Tags },
  { href: "/stok", label: "Stok", icon: Boxes },
  { href: "/pembelian", label: "Pembelian", icon: Truck },
  { href: "/penerimaan", label: "Penerimaan", icon: ClipboardList },
  { href: "/hutang", label: "Hutang", icon: HandCoins },
];

function NavigationLink({ item }: { item: NavItem }) {
  const Icon = item.icon;
  return (
    <Link
      href={item.href}
      className="inline-flex min-h-11 shrink-0 items-center gap-2 rounded-lg px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
    >
      <Icon className="size-4" aria-hidden />
      {item.label}
    </Link>
  );
}

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
    <div className="min-h-screen bg-muted/20">
      <header className="border-b bg-background print:hidden">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3 px-4 py-3 sm:px-6">
          <Link
            href={workspace?.mode === "bengkel" ? "/bengkel" : "/toko"}
            className="flex items-center gap-2 font-semibold"
          >
            {workspace?.mode === "bengkel" ? (
              <Wrench className="size-5" aria-hidden />
            ) : (
              <Store className="size-5" aria-hidden />
            )}
            {workspace?.mode === "bengkel" ? "Bengkel" : "Toko Bangunan"}
          </Link>
          <div className="flex items-center gap-2">
            {workspace ? (
              <Link
                href="/pilih-usaha"
                className="inline-flex min-h-11 items-center rounded-lg border px-3 text-sm font-medium hover:bg-muted"
              >
                {workspace.tenantName}
              </Link>
            ) : null}
            <LogoutButton />
          </div>
        </div>
        {workspace ? (
          <nav
            aria-label="Navigasi utama"
            className="mx-auto flex max-w-7xl gap-1 overflow-x-auto px-3 pb-2 sm:px-5"
          >
            <NavigationLink
              item={{
                href: workspace.mode === "bengkel" ? "/bengkel" : "/toko",
                label: "Beranda",
                icon: LayoutDashboard,
              }}
            />
            {workspace.mode === "bengkel" ? (
              <>
                <NavigationLink item={{ href: "/bengkel/work-order", label: "Work Order", icon: ClipboardList }} />
                <NavigationLink item={{ href: "/kendaraan", label: "Kendaraan", icon: CarFront }} />
              </>
            ) : null}
            {sharedOperations.map((item) => (
              <NavigationLink key={item.href} item={item} />
            ))}
            {inventoryItems.map((item) => (
              <NavigationLink key={item.href} item={item} />
            ))}
            <NavigationLink item={{ href: "/pelanggan", label: "Pelanggan", icon: UsersRound }} />
            <NavigationLink item={{ href: "/pemasok", label: "Pemasok", icon: Truck }} />
            {canManage ? (
              <NavigationLink item={{ href: "/pengaturan", label: "Pengaturan", icon: Settings }} />
            ) : null}
          </nav>
        ) : null}
      </header>
      <main className="mx-auto max-w-7xl p-4 sm:p-6 print:p-0">{children}</main>
    </div>
  );
}
