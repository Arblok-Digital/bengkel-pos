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
- `tenant_id` tidak boleh berubah lewat UPDATE. Setiap tabel ber-`tenant_id` wajib memasang trigger `public.prevent_tenant_change` (lihat migrasi `0003`), dengan tes memakai aktor yang owner di dua tenant — policy `WITH CHECK` saja tidak cukup.
- Role `dev` adalah operator platform (akses lintas tenant). **Hanya operator (SQL/service role) yang boleh membuat dev pertama**; policy `memberships` wajib menolak owner/admin memberi, mengubah, atau menghapus role `dev` (lihat migrasi `0005`), dan tesnya wajib memuat kasus negatif tersebut.
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
npm run dev                      # jalankan app (otomatis menyalakan Supabase lokal)
npm run db:up                    # nyalakan Supabase lokal (db, auth, rest, kong saja)
npm run db:down                  # matikan container bengkel-pos, data tetap aman
npm run db:reset                 # terapkan semua migrasi + seed (wajib sebelum E2E)
npm run db:status                # container, kesehatan API/relay, pemakaian RAM
npm run wsl:off                  # db:down lalu matikan seluruh WSL (bebaskan RAM)
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
4. Jika menyentuh layar kasir, shift, penjualan, piutang, work order, atau struk: jalankan E2E untuk alur terkait sesuai **Bagian 11** dan tempel output mentahnya.
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

## 11. Aturan Wajib Tes E2E

Bagian ini mengikat. Klaim "E2E hijau" tanpa mengikuti urutan di bawah dianggap **tidak ada bukti**.

### 11.1 Urutan wajib (tidak boleh diacak)

E2E selalu dijalankan **di atas DB yang baru di-reset**, karena spec mengandalkan seed dan data sisa spec lain merusak tes SQL berikutnya.

```bash
# 1. reset DB (wrapper WSL; versi CLI dibaca dari package.json)
npm run db:reset
# 2. tes pgTAP (belum ada skrip npm; jalankan CLI dari WSL sesuai bagian Isolasi)
wsl bash -lc "cd /tmp && npx --yes supabase@2.122.0 --workdir /mnt/c/Users/ARBLOK/projects/bengkel test db"
# 3. baru E2E (dev server menyala otomatis lewat playwright.config webServer)
npx playwright test e2e/<spec-terkait>.spec.ts
```

- Versi Supabase CLI **wajib sama** dengan yang dikunci di `package.json` (saat ini `^2.122.0`). Jangan mengarang versi lain.
- `npx playwright test <spec>` untuk alur terkait **wajib**, `npm run e2e` penuh hanya pelengkap.
- Jangan menjalankan spec terkait berkali-kali sampai kebetulan lulus. Satu kali di DB bersih = bukti. Retry bawaan config (`retries: 1`) **bukan** alasan untuk menganggap lulus; kalau lulus hanya di percobaan kedua, itu **gagal** dan wajib dilaporkan.
- Jangan menyalakan `--repeat-each`, `--workers > 1`, atau `--retries 0/5` untuk mengubah hasil. Konfigurasi hanya boleh diubah kalau task-nya memang tentang konfigurasi Playwright.

### 11.2 Bukti yang wajib ditempel

Di laporan akhir tempel output mentah, minimal:

```
Running 1 test using 1 worker
  ✓  1 e2e/<spec>.spec.ts:<baris>:<kolom> › <nama tes> (<durasi>)
  1 passed (<durasi total>)
```

Yang **tidak** dihitung bukti: "sudah dites", "hijau", screenshot tanpa nama spec, ringkasan buatan sendiri, atau output dari sesi/commit lain. Kalau test di-skip (`-`), sebutkan dan jelaskan alasannya.

### 11.3 Cara membuktikan kegagalan itu bawaan (bukan akibat perubahan kamu)

Dilarang menulis "gagal bawaan" tanpa bukti. Untuk setiap kegagalan yang kamu klaim di luar scope, sertakan **ketiganya**:

1. Perintah persis yang dijalankan dan output mentah kegagalannya (nama spec, baris, assertion yang gagal).
2. Hasil `npx playwright test e2e/<spec>.spec.ts` **sendirian** di DB yang baru di-reset (bukan di tengah suite penuh).
3. Sebab konkret yang bisa dicek orang lain: tunjuk baris `supabase/seed.sql`, `e2e/helpers.ts`, atau commit yang memperkenalkannya (`git log -S "<teks assertion>"`). "Sepertinya memang begitu dari dulu" bukan bukti.

Kalau ketiganya tidak bisa dipenuhi, perlakukan sebagai **kegagalan task kamu**: perbaiki atau nyatakan task `terblokir`, jangan `selesai`.

### 11.4 Larangan saat tes merah

- Dilarang menghapus, melewati (`test.skip`, `test.fixme`), atau mengomentari tes yang gagal supaya hijau.
- Dilarang memperlonggar assertion (mis. `toHaveURL("/")` → `toHaveURL(/.*/)`, menambah timeout besar, `expect(...).toBeTruthy()` menggantikan cek nilai).
- Dilarang mengubah data seed produksi/seed utama hanya supaya tes lulus, kecuali seed itu memang salah dan perbaikannya masuk task yang sama + dijelaskan.
- Dilarang menghapus langkah di dalam spec (mis. melewati `ensureShift`) untuk menghindari error.
- Kalau tes gagal karena bug aplikasi: perbaiki aplikasinya, bukan tesnya. Kalau tes gagal karena ekspektasi tes yang sudah usang: perbaiki tesnya sambil menjelaskan di laporan mengapa ekspektasi lama salah.

### 11.5 Aturan menulis spec baru / mengubah spec

- Login **wajib** lewat `helpers.login(page)`. Jangan menyalin isi login ke spec.
- Jangan assert `toHaveURL("/")`: `/` selalu redirect ke `/(bengkel|toko)`. Pakai pola regex.
- Data uji wajib unik per run (`Date.now()` / `crypto.randomUUID()` di luar render React) supaya tidak bentrok dengan sisa run sebelumnya.
- Satu spec harus bisa lulus **sendirian** di DB bersih. Jangan bergantung pada spec lain yang jalan lebih dulu, pada shift yang kebetulan masih terbuka, atau pada stok yang kebetulan tersisa.
- Bersihkan state yang kamu buka sendiri (`closeShift` bila spec membuka shift) agar suite penuh tidak saling merusak.
- Untuk alur yang menyentuh stok/uang, assert **nilai** yang terlihat user (total rupiah, status, sisa stok), bukan sekadar "halaman terbuka".

### 11.6 Spec yang diketahui sudah usang (per 28 Okt 2026)

Kegagalan berikut sudah terverifikasi **bawaan** dan **bukan** bukti sebuah task selesai:

| Spec | Sebab |
| --- | --- |
| `e2e/stock.spec.ts` | Seed T5.2: stok Semen 500 − 18 = 482, min 5, jadi badge "Aman" padahal spec mengharapkan "Menipis". |
| `e2e/low-stock.spec.ts` | Sama seperti `stock.spec.ts` (ambang minimum seed tidak lagi memicu status menipis). |
| `e2e/auth-staff.spec.ts` | Assert `toHaveURL("/")` sebelum redirect selesai (regresi sejak commit `ca59927`). |
| `e2e/catalog.spec.ts` | Mencari link "Katalog" yang tidak ada di mode bengkel; juga `toHaveURL("/")`. |
| `e2e/sale-admin.spec.ts` | Lulus sendirian; gagal di suite penuh karena state shift/stok dari spec sebelumnya. |

Aturan: kalau task kamu menyentuh area spec di tabel ini, **kamu wajib memperbaikinya di task itu** (test lama yang salah, bukan fitur). Kalau tidak menyentuh, laporkan sebagai catatan di luar scope beserta output mentahnya.

### 11.7 Ringkasan yang bisa dicek mesin

Sebelum commit, jawab di laporan:

- [ ] `npm run db:reset` dijalankan setelah perubahan migrasi terakhir?
- [ ] `supabase test db` hijau (tempel `Files=..., Tests=..., Result: PASS`)?
- [ ] `npx playwright test e2e/<spec terkait>` hijau di DB bersih, tempel outputnya?
- [ ] Semua kegagalan lain yang terlihat sudah dibuktikan bawaan (11.3) atau dilaporkan `terblokir`?
- [ ] Tidak ada assertion yang diperlonggar, tes dihapus, atau `test.skip` baru?

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
