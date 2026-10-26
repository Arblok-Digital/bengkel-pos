import { Button } from "@/components/ui/button";

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-8 p-8">
      <div className="text-center">
        <h1 className="text-3xl font-bold tracking-tight">
          Kasir Bengkel &amp; Toko Bangunan
        </h1>
        <p className="text-muted-foreground mt-2 text-lg">
          Aplikasi POS multi-tenant, offline-capable, Bahasa Indonesia.
        </p>
      </div>
      <Button className="h-12 min-w-44 min-h-12 text-base">
        Buka Kasir
      </Button>
      <p className="text-muted-foreground text-sm">
        Fase 0 &mdash; fondasi repositori sedang dipasang.
      </p>
    </main>
  );
}
