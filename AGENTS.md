# AGENTS.md

Aplikasi kasir (POS) untuk **bengkel** dan **toko bangunan**. Multi-tenant, offline-capable, Bahasa Indonesia.
Dokumen desain lengkap ada di `ARCHITECTURE.md`. File ini adalah aturan kerja kamu sebagai agent. Kalau keduanya bertentangan, **berhenti dan tanya**.

---

## 1. Cara Memulai Setiap Sesi

1. Baca file ini sampai habis.
2. Baca **hanya bagian** `ARCHITECTURE.md` yang relevan dengan task (Bagian 2 untuk stack, Bagian 4 untuk tabel yang disentuh, Bagian 9 untuk task-nya). Jangan membaca seluruh dokumen kalau tidak perlu.
3. Cek `git status` dan `git log -5` untuk tahu kondisi terakhir.
4. Kerjakan **satu task** (misal `T4.2`). Bukan dua, bukan "sekalian fase berikutnya".
5. Tulis rencana singkat (maksimal 8 baris) sebelum mengubah file.

---

## 2. Stack (Terkunci)

Next.js 16 App Router + TypeScript strict, Tailwind + shadcn/ui, Supabase (Postgres, Auth, RLS), Zod, TanStack Query, Vitest, Playwright, Dexie + Serwist untuk offline.
(Upgrade 15 → 16 disetujui Ardi untuk menutup vulnerability postcss di dalam bundel Next 15; keputusan setelah bagian ini.)

Dilarang menambah dependensi di luar daftar ini tanpa izin. Kalau merasa butuh, tulis alasannya dan tanya.

---

## 3. Aturan Keras (Tidak Boleh Dilanggar)

**Uang**
- Semua uang **integer rupiah** (`bigint` di DB, `number` bulat di TS). Dilarang `float`, dilarang `toFixed` untuk menghitung.
- Semua format/hitung uang lewat `src/lib/money.ts`. Jangan menulis ulang logika uang di tempat lain.

**Stok**
- Dilarang `UPDATE stock_levels` atau mengubah stok langsung. Stok hanya berubah lewat insert ke `stock_movements`.
- Stok dipotong **hanya** di `create_sale` (termasuk penjualan dari work order). Jangan memotong stok di tempat lain.

**Transaksi & data**
- Mutasi yang menyentuh uang atau stok = **satu fungsi RPC Postgres atomik**, bukan beberapa panggilan dari client.
- Semua RPC transaksi **idempoten** lewat `client_uuid`.
- ID dokumen transaksi dibuat di client (UUID v7).
- Harga dan HPP **disalin** ke baris item saat transaksi. Jangan merujuk harga produk saat laporan.
- Dokumen yang sudah `paid`/`posted` tidak diedit. Koreksi lewat void/retur + alasan + `audit_logs`.
- Total transaksi **dihitung ulang di server**. Jangan percaya total dari client.

**Skema & keamanan**
- Perubahan skema = file migrasi baru di `supabase/migrations/` dengan nomor berurutan. **Jangan mengedit migrasi yang sudah di-commit.**
- Setiap tabel bisnis wajib punya `tenant_id`, RLS aktif, dan indeks yang diawali `tenant_id`. Policy RLS **per perintah**: satu policy `for select ... using (public.is_member(tenant_id))` untuk semua member, dan policy tulis terpisah per INSERT/UPDATE/DELETE yang memeriksa `public.has_role(tenant_id, roles[])` (owner/admin). Tabel baru wajib punya pasangan tes positif/negatif pgTAP per perintah, dan setiap tes negatif wajib diikuti verifikasi (sebagai postgres) bahwa data tidak berubah.
- Tenant tidak boleh di-hard-delete lewat API (tanpa policy DELETE); pembuatan tenant hanya lewat RPC onboarding (T1.2).
- `cost_price`, `unit_cost`, dan nilai aset stok **tidak boleh terbaca** oleh role `kasir`/`mekanik` (pakai view tanpa kolom biaya).
- Service role key hanya di server. Jangan pernah di kode client atau di commit.
- Jangan commit `.env*`. Jangan mencetak secret ke log atau ke output kamu.

**UI**
- Semua teks UI Bahasa Indonesia. Format `Rp 1.250.000`, tanggal `26 Okt 2026`.
- Target sentuh minimal 44 px. Layar kasir harus bisa dipakai tanpa mouse (shortcut di `ARCHITECTURE.md` Bagian 6).
- Tidak ada query Supabase langsung di komponen UI. Lewat `src/features/<domain>/queries.ts`.
- Jangan menyembunyikan fitur hanya di UI untuk membatasi role. Batasi juga di DB/server.

---

## 4. Struktur & Konvensi

- Komponen halaman tipis. Logika di `src/features/<domain>/` (`components`, `hooks`, `schema.ts`, `queries.ts`, `actions.ts`).
- Schema Zod satu sumber untuk client dan server. Jangan menduplikasi tipe.
- Tipe DB di-generate ke `src/lib/supabase/types.ts` (`supabase gen types`). Jangan edit manual.
- Nama file: `kebab-case`. Komponen: `PascalCase`. Tabel/kolom DB: `snake_case`. Kode dan komentar teknis boleh Inggris, teks yang tampil ke user Indonesia.
- Fungsi pendek, satu tujuan. Tidak ada `any`. Tidak ada `// @ts-ignore` tanpa komentar alasan.
- Jangan refactor kode di luar task. Kalau melihat masalah di luar scope, **catat** di akhir laporan, jangan diperbaiki diam-diam.

---

## 5. Perintah Standar

```bash
npm run dev                      # jalankan app
npm run lint
npm run typecheck                # tsc --noEmit
npm run test                     # vitest
npm run e2e                      # playwright
supabase start                   # DB lokal
supabase db reset                # terapkan semua migrasi + seed
supabase test db                 # tes pgTAP (RLS + RPC)
supabase gen types typescript --local > src/lib/supabase/types.ts
```

Kalau salah satu perintah belum ada di `package.json`, tambahkan sesuai nama di atas (itu bagian dari task T0.1), jangan mengarang nama lain.

---

## 6. Definisi Selesai (Wajib Sebelum Bilang "Selesai")

Sebuah task **belum selesai** sampai semua ini benar:

1. Semua poin "Selesai bila" task tersebut di `ARCHITECTURE.md` terpenuhi.
2. `npm run lint && npm run typecheck && npm run test` hijau.
3. Jika menyentuh DB: `supabase db reset && supabase test db` hijau, dan ada tes SQL untuk RPC/RLS yang baru.
4. Jika menyentuh layar kasir, shift, penjualan, atau piutang: `npm run e2e` untuk alur terkait hijau.
5. Perubahan sudah di-commit.

**Tempel output mentah** dari perintah verifikasi di laporan akhir. Dilarang menulis "sudah dites" atau "berhasil" tanpa output. Kalau sebuah tes dilewati atau gagal, katakan terang-terangan.

---

## 7. Format Laporan Akhir

```
TASK: <ID> <judul>
STATUS: selesai | sebagian | terblokir

FILE BERUBAH:
- path (baru/diubah): alasan singkat

MIGRASI BARU: <nama file atau "tidak ada">

VERIFIKASI (output mentah):
<lint/typecheck/test/db test/e2e>

CATATAN DI LUAR SCOPE:
- <temuan yang tidak diperbaiki>

PERLU KEPUTUSAN:
- <pertanyaan, atau "tidak ada">
```

---

## 8. Kapan Berhenti dan Bertanya

Berhenti dan tanya (jangan menebak) jika:
- Spesifikasi ambigu atau dua bagian dokumen bertentangan.
- Task butuh perubahan di luar Bagian 2 `ARCHITECTURE.md` (stack, aturan uang/stok).
- Perlu dependensi baru, mengubah migrasi lama, atau menghapus data.
- Tes yang seharusnya hijau gagal dan penyebabnya bukan di perubahan kamu.

**Anti-loop:** kalau error yang sama muncul **3 kali berturut-turut** setelah 3 percobaan perbaikan berbeda, berhenti. Laporkan: error persisnya, apa yang sudah dicoba, dan dugaan penyebab. Jangan mengulang perbaikan yang sama dengan variasi kecil.

Jika konteks sudah panjang dan kamu mulai lupa keputusan awal, ringkas kondisi saat ini (apa yang selesai, apa yang tersisa, file terkait) lalu minta sesi baru. Satu task = satu sesi lebih baik daripada satu sesi panjang yang bingung.

---

## 9. Git

- Branch per task: `feat/T4-2-create-sale`.
- Commit kecil dan sering. Format: `feat(pos): ...`, `fix(stock): ...`, `db(sales): ...`, `test(ar): ...`, `chore: ...`.
- Jangan `git push --force`, jangan `git reset --hard` pada pekerjaan yang belum di-commit, jangan menghapus branch.
- Migrasi dan kode yang bergantung padanya masuk di commit yang sama atau berurutan di branch yang sama.

---

## 10. Hal yang Sering Salah (Cek Sebelum Selesai)

- [ ] Ada angka uang yang dihitung dengan `*` atau `/` langsung tanpa `money.ts`?
- [ ] Ada tabel baru tanpa `tenant_id`, RLS, atau indeks?
- [ ] Ada tempat yang mengubah stok tanpa `stock_movements`?
- [ ] Qty desimal (0,5 sak, 2,5 m) sudah diuji di perhitungan dan di stok?
- [ ] Konversi satuan (sak ↔ kg) sudah dipakai di total **dan** di stok base?
- [ ] RPC sudah aman dipanggil dua kali dengan `client_uuid` sama?
- [ ] Role `kasir` tidak bisa membaca modal/HPP lewat query langsung?
- [ ] Stok menipis ditandai merah+tebal di daftar yang kamu ubah?
- [ ] Teks UI baru sudah Bahasa Indonesia dan format rupiah benar?
- [ ] Status koneksi/antrean sinkron tidak rusak oleh perubahan kamu (setelah Fase 10)?

<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## Isolasi dari project lain
- Bekerja hanya di C:\Users\ARBLOK\projects\bengkel. Dilarang membaca/menulis/menghapus di luar folder ini (kecuali cache npm/playwright dan resource Docker milik project ini).
- Dilarang: `npm install -g`, mengubah PATH, Node global, git config global, .wslconfig, pengaturan Docker Desktop, file hosts, `docker system prune`.
- Dilarang `docker stop/rm/kill/volume rm` pada container atau volume yang namanya tidak mengandung `bengkel-pos`.
- Stapel Docker milik project ini: **daemon Docker di dalam WSL Ubuntu** (bukan Docker Desktop). Semua perintah Docker HANYA dari WSL, dan HANYA pada resource bernama `*bengkel-pos*`.
- Container `n8n`, `keel-postgres-1`, `keel-redis-1`, dan service Postgres (5432) serta Redis (6379) di WSL Ubuntu adalah **milik project lain — tidak boleh disentuh**. Jangan menghentikan container project lain; pemiliknya yang menanganinya.
- Supabase: HANYA lokal. Dilarang `supabase link`, `supabase db push`, flag `--linked`, atau memakai kredensial/project Supabase remote mana pun, termasuk lewat MCP.
- Supabase CLI dijalankan dari WSL dengan `npx supabase@<versi> --workdir /mnt/c/Users/ARBLOK/projects/bengkel <cmd>`; `<versi>` harus sama dengan yang dikunci di `package.json`. Jangan menjalankan `npm install` atau perintah yang menulis ke `node_modules` dari WSL.
- Sebelum perintah yang menyalakan/mematikan layanan (`supabase start/stop/db reset`, perintah docker), tampilkan perintahnya dan konfirmasi `project_id` + port di supabase/config.toml sudah milik project ini.
