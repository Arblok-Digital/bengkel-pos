"use client";

import { useRouter } from "next/navigation";

import { Button } from "@/components/ui/button";
import { getCatalogDb } from "@/lib/offline/catalog-db";
import { clearOfflineCatalog } from "@/lib/offline/catalog-store";
import { createClient } from "@/lib/supabase/client";

export function LogoutButton() {
  const router = useRouter();
  async function onClick() {
    try {
      await clearOfflineCatalog(getCatalogDb());
    } catch {
      // Cache gagal dihapus (mis. IndexedDB diblokir): logout tetap jalan.
    }

    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }
  return (
    <Button variant="outline" onClick={onClick}>
      Keluar
    </Button>
  );
}
