import Link from "next/link";

import type { LowStockData } from "@/features/inventory/queries";

export function LowStockBanner({ data }: { data: LowStockData | null }) {
  const count = data?.rows.length ?? 0;

  if (!data || count === 0) return null;

  return (
    <Link
      href="/stok/menipis"
      className="flex min-h-11 items-center justify-between gap-3 rounded-lg border border-destructive/40 bg-destructive/5 px-4 py-3 text-sm hover:bg-destructive/10"
    >
      <span>
        <span className="font-semibold text-destructive">Stok menipis</span>
        <span className="text-muted-foreground">
          {" "}
          &middot; {data.tenantName} &middot; {count} barang di bawah stok
          minimum
        </span>
      </span>
      <span className="font-semibold text-destructive" aria-hidden>
        &rarr;
      </span>
    </Link>
  );
}
