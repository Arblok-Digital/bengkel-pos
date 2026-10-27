# Kasir Bengkel & Toko Bangunan

Aplikasi POS multi-tenant, offline-capable, Bahasa Indonesia.
Desain lengkap: `ARCHITECTURE.md` — aturan kerja: `AGENTS.md`.

## Dokumentasi

| Berkas | Isi |
| --- | --- |
| `ARCHITECTURE.md` | Desain lengkap: stack, model data, pola RLS, alur transaksi, rencana fase T0.1–T11.5. |
| `AGENTS.md` | Aturan kerja agent: uang integer, stok lewat `stock_movements`, RPC atomik, RLS per perintah. |
| [`docs/database.md`](docs/database.md) | Arsitektur database: ERD, daftar tabel + kolom, policy RLS, daftar RPC. |
| [`docs/database-schema.sql`](docs/database-schema.sql) | Dump skema `public` (`pg_dump --schema-only`) — bisa dibaca tanpa menyalakan Supabase. |
| `supabase/migrations/` | Sumber kebenaran skema, berurutan dan tidak boleh diedit. |
| `supabase/tests/` | Tes pgTAP untuk RLS, trigger, dan RPC. |
| `e2e/` | Tes Playwright alur nyata (kasir, shift, pembayaran, struk, PWA). |

Data demo (khusus lokal, dari `supabase/seed.sql`): tenant **Bengkel Maju Jaya**,
outlet **Outlet Utama**, akun `admin@bengkel.test` / `bengkel123`.
Jangan dipakai di produksi.

## Prasyarat

- Node.js (npm) di Windows — semua `npm run dev`, test, build, install **hanya di Windows**.
- Docker daemon di dalam **WSL Ubuntu** — semua operasi database/Supabase **hanya via WSL**.
  Detail isolasi: bagian "Isolasi dari project lain" di `AGENTS.md`.

## Perintah harian (Windows)

```powershell
npm run dev          # jalankan app (Next.js 16, Turbopack)
npm run lint
npm run typecheck    # tsc --noEmit
npm run test         # vitest
npm run e2e          # playwright
```

## Supabase lokal (hanya lewat WSL Ubuntu)

CLI dijalankan dari WSL dengan versi yang **harus sama** dengan devDependency
`supabase` di `package.json` (saat ini `2.122.0`) dan flag `--workdir`:

```bash
# di WSL Ubuntu — versi CLI HARUS sesuai package.json
npx supabase@2.122.0 --workdir /mnt/c/Users/ARBLOK/projects/bengkel start …
```

Panggilan dari Windows shell tetap berbentuk wrapper di bawah supaya semuanya
konsisten lepas dari lokasi kerja (lihat blok kode di bawah).

### Start / Stop

```bash
# WSL — start (hemat resource; T0.2 hanya perlu db + kong + auth + rest)
cd /tmp && npx --yes supabase@2.122.0 --workdir /mnt/c/Users/ARBLOK/projects/bengkel \
  start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor --yes

# WSL — setelah selesai sesi (RAM bebas, data tetap tersimpan di volume docker)
cd /tmp && npx --yes supabase@2.122.0 --workdir /mnt/c/Users/ARBLOK/projects/bengkel stop
```

Nilai project_id + port lokal (sesuai `supabase/config.toml`):

| Nilai            | hasil  |
| ---------------- | ------ |
| `project_id`     | `bengkel-pos` |
| API (kong/gateway) | `http://127.0.0.1:55321` |
| Database (postgres) | `postgresql://postgres:postgres@127.0.0.1:55322/postgres` |
| Studio           | `http://127.0.0.1:55323` (tidak dijalankan — dicomot lewat `-x studio`) |

### Migrasi & tes DB

```bash
# WSL — aplikasikan seluruh migrasi + seed dari nol
cd /tmp && npx --yes supabase@2.122.0 --workdir /mnt/c/Users/ARBLOK/projects/bengkel \
  db reset

# WSL — jalankan tes pgTAP di supabase/tests/*.test.sql
cd /tmp && npx --yes supabase@2.122.0 --workdir /mnt/c/Users/ARBLOK/projects/bengkel \
  test db
```

### Generate type database → TypeScript

```bash
# WSL — output ke stdout; diredirect oleh shell WSL ke file project (LF, bukan CRLF)
cd /mnt/c/Users/ARBLOK/projects/bengkel && \
  npx --yes supabase@2.122.0 --workdir /mnt/c/Users/ARBLOK/projects/bengkel \
  gen types typescript --local > src/lib/supabase/types.ts
```

### Workaround port WSL2 (jika `127.0.0.1:55321` menolak koneksi)

Setelah container Supabase restart, port yang dipublikasikan Docker kadang tidak ikut diteruskan ke Windows. Cek dengan `Test-NetConnection 127.0.0.1 -Port 55321`. Jika gagal tetapi `curl` dari WSL berhasil, jalankan relay di WSL pada port baru dan arahkan `.env.local` ke port itu:

```bash
# WSL — biarkan berjalan selama sesi dev
python3 /mnt/c/Users/ARBLOK/projects/bengkel/scripts/wsl-port-relay.py 56021 127.0.0.1 55321
```

```dotenv
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:56021
```

Restart `npm run dev` setelah mengubah env. Ini hanya workaround lingkungan WSL2,
bukan bagian aplikasi.

## Larangan (ringkas)

- Dilarang `npm install -g` Apa pun, atau `npm install`/install node_modules dari WSL.
- Dilarang menyentuh container/volume Docker yang namanya tidak memuat `bengkel-pos`
  dan milik project lain (`n8n*`, `keel*`, Postgres/Redis WSL di 5432/6379).
- Supabase **hanya lokal**; `supabase link`, `supabase db push`, kredensial remote
  dilarang. Service role key hanya boleh muncul di server, tidak di client/commit.
