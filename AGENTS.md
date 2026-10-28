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
6. Baca **Bagian 11** sebelum mulai. Kalau task menyentuh area di tabel 11.1, E2E **wajib** dijalankan dan outputnya ditempel — bukan opsional.

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

Sebuah task **belum selesai** sampai **semua** poin ini benar dan dibuktikan dengan output mentah. Tidak ada pengecualian "karena waktunya mepet".

1. Semua poin "Selesai bila" task tersebut di `ARCHITECTURE.md` terpenuhi.
2. `npm run lint && npm run typecheck && npm run test` → exit 0, tanpa error.
3. Jika menyentuh DB: `npm run db:reset` lalu `supabase test db` → `Result: PASS`, dan ada tes SQL baru untuk RPC/RLS yang baru.
4. E2E sesuai **Bagian 11**: spec area terkait lulus **sendirian**, lalu **suite penuh `npm run e2e`** di DB yang baru di-reset → `0 failed`, `0 flaky`. "Spec terkait hijau" saja **bukan** definisi selesai.
5. Audit diff (Bagian 11.8): hanya file yang relevan, tidak ada `.env*`, secret, `console.log` sisa debug, `test.skip`, `test.only`, atau file `test-results/`.
6. Perubahan sudah di-commit (dan di-push bila diminta).
7. Laporan memakai format Bagian 7 dan menempel output **asli** dari perintah yang benar-benar dijalankan.

**Larangan klaim (laporan langsung dianggap tidak sah):**
- "sudah dites", "harusnya jalan", "mestinya aman", "kemungkinan beres", "di lokal aman".
- Hanya menempel exit code tanpa output perintah.
- Menempel output dari sesi/commit lain, atau output yang diedit.
- Mengklaim suite penuh hijau padahal hanya menjalankan sebagian spec.
- Mengklaim "gagal bawaan" tanpa bukti tiga poin di Bagian 11.3.
- Menganggap `flaky` sebagai lulus; `flaky` = **gagal**.

Kalau satu poin saja gagal, status task **wajib** `sebagian` atau `terblokir` — bukan `selesai`.

Pengecualian: perubahan **murni dokumentasi** (mis. `AGENTS.md`, `docs/*.md`) tidak wajib langkah B–F, tetapi tetap wajib audit diff dan alasannya disebut di laporan. Kalau dokumen itu mengubah perilaku agent (seperti file ini), perlakukan sebagai perubahan penting: baca ulang Bagian 11 setelah mengeditnya.

---

## 7. Format Laporan Akhir

```
TASK: <ID> <judul>
STATUS: selesai | sebagian | terblokir

FILE BERUBAH:
- path (baru/diubah): alasan singkat

MIGRASI BARU: <nama file atau "tidak ada">

VERIFIKASI (output mentah, sesuai urutan Bagian 11.1):
LINT:
<output>
TYPECHECK:
<output>
VITEST:
<output>
DB RESET:
<output>
PGTAP:
<output>
E2E TERKAIT:
<output>
E2E PENUH:
<output>

AUDIT DIFF:
- <hasil git status/diff: bersih atau file di luar scope yang dikeluarkan>

CATATAN DI LUAR SCOPE:
- <temuan yang tidak diperbaiki>

PERLU KEPUTUSAN:
- <pertanyaan, atau "tidak ada">
```

`STATUS: selesai` hanya sah bila checklist Bagian 11.7 lengkap. Kalau ada satu kegagalan, tulis `sebagian`/`terblokir` beserta output gagalnya — jangan memilih `selesai` lalu menaruh kegagalan di catatan.

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
- [ ] Checklist verifikasi Bagian 11.7 lengkap dan output asli ditempel?
- [ ] `npm run e2e` penuh `0 failed`, `0 flaky` (bukan hanya spec terkait)?
- [ ] Tidak ada assertion yang diperlonggar, tes dihapus/di-skip, atau `test.only`?
- [ ] Diff sudah diaudit: tidak ada secret, `console.log`, atau file di luar scope?

## 11. Aturan Wajib Tes E2E

Bagian ini mengikat. Klaim "E2E hijau" tanpa mengikuti urutan di bawah dianggap **tidak ada bukti**.

**E2E bukan opsional.** Kalau task menyentuh salah satu area di tabel 11.1, melewati E2E berarti task berstatus **sebagian**, bukan **selesai** — sekalipun lint/typecheck/unit test hijau.

### 11.1 Urutan wajib (tidak boleh diacak)

E2E selalu dijalankan **di atas DB yang baru di-reset**. Suite penuh **wajib** — bukan hanya spec area terkait — karena data/state dari spec lain bisa merusak alur yang kelihatan tidak berhubungan.

```bash
# A. Gerbang cepat
npm run lint
npm run typecheck
npm run test

# B. DB bersih
npm run db:reset

# C. Tes SQL
wsl bash -lc "cd /tmp && npx --yes supabase@2.122.0 --workdir /mnt/c/Users/ARBLOK/projects/bengkel test db"

# D. Spec area terkait, sendirian (bukti spec mandiri)
#    Bisa lebih dari satu file, mis. e2e/stock.spec.ts e2e/low-stock.spec.ts
npx playwright test e2e/<spec-area>.spec.ts

# E. Reset lagi — langkah D mengubah data
npm run db:reset

# F. Suite penuh (WAJIB, ini bukti akhir)
npm run e2e
```

- Versi Supabase CLI **wajib sama** dengan yang dikunci di `package.json` (saat ini `^2.122.0`). Jangan mengarang versi lain.
- Sebelum langkah B/E, tampilkan perintah reset dan pastikan `project_id = "bengkel-pos"` serta port di `supabase/config.toml` masih milik project ini (lihat bagian Isolasi).
- Langkah A–F semuanya wajib untuk task yang menyentuh kode/alur. Melewati salah satu = verifikasi tidak sah.
- Urutan tidak boleh diacak: menjalankan E2E sebelum reset, atau suite penuh sebelum spec terkait, membuat hasilnya tidak bisa dipercaya.
- Jangan menjalankan spec berkali-kali sampai kebetulan lulus. Satu kali di DB bersih = bukti. Retry bawaan (`retries: 1`) **bukan** alasan lulus; kalau lulus hanya di percobaan kedua, itu **gagal** dan wajib dilaporkan.
- Jangan menyalakan `--repeat-each`, `--workers > 1`, `--retries`, `test.describe.configure({ retries })`, atau mengubah konfigurasi Playwright untuk mengubah hasil. Konfigurasi hanya boleh diubah kalau task-nya memang tentang konfigurasi Playwright, dan itu wajib dijelaskan.
- Suite penuh harus dijalankan **setelah** perubahan kode terakhir. Kalau setelah suite penuh kamu mengubah kode lagi, ulangi dari langkah B.

**Peta area → spec (wajib dipakai, jangan menebak):**

| Area yang kamu ubah | Spec yang wajib dijalankan |
| --- | --- |
| Kasir, keranjang, pembayaran, hold | `e2e/pos.spec.ts`, `e2e/payment.spec.ts` |
| Shift, modal awal, tutup kasir | `e2e/shift.spec.ts`, `e2e/pos.spec.ts` |
| Penjualan, retur, void, struk | `e2e/sale-admin.spec.ts`, `e2e/receipt.spec.ts` |
| Kredit/tempo, piutang, cicilan | `e2e/credit-sale.spec.ts`, `e2e/receivables.spec.ts` |
| Stok, penyesuaian, opname, stok menipis | `e2e/stock.spec.ts`, `e2e/low-stock.spec.ts`, `e2e/stock-adjustment.spec.ts` |
| Work order, kendaraan | `e2e/work-order.spec.ts` |
| Produk, katalog, impor CSV | `e2e/products.spec.ts`, `e2e/catalog.spec.ts`, `e2e/import.spec.ts` |
| Pelanggan, pemasok | `e2e/customers.spec.ts` |
| Auth, staf, pengaturan, role | `e2e/auth-staff.spec.ts` |
| Offline, Dexie, outbox, PWA | `e2e/offline-sale.spec.ts`, `e2e/offline-catalog.spec.ts`, `e2e/offline-midflight.spec.ts`, `e2e/pwa.spec.ts` |

- Jika area yang kamu sentuh **belum punya spec**, kamu wajib menulis spec baru untuk alur utamanya — bukan menandai "tidak ada spec" lalu selesai.
- Jika satu perubahan menyentuh beberapa area, jalankan gabungan spec-nya dalam satu perintah.
- Perubahan murni dokumentasi (mis. file ini) tidak wajib E2E; sebutkan alasannya di laporan.

### 11.2 Bukti yang wajib ditempel

Tempel output **asli** di laporan, dalam blok kode, untuk **setiap** langkah A–F. Bentuk minimal yang diterima:

```
$ npm run lint
(exit 0, tanpa output error)

$ npm run typecheck
(exit 0, tanpa output error)

$ npm run test
Test Files  10 passed (10)
     Tests  94 passed (94)

$ npm run db:reset
database: reset bengkel-pos (migrasi + seed) ...
database: reset selesai

$ npx playwright test e2e/<spec-area>.spec.ts
1 passed (17.9s)

$ npm run e2e
22 passed (2.9m)
```

Aturan penempelan:
- Sertakan baris ringkasan **dan** nama spec yang relevan. Kalau output sangat panjang, potong bagian tengah, jangan potong baris ringkasan.
- Angka harus **aktual** dari run itu, bukan template. Kalau jumlah tes berubah karena kamu menambah spec, tulis jumlah barunya dan jelaskan.
- `npm run e2e` wajib menunjukkan `0 failed` dan `0 flaky`. Kalau ada baris `x`, `retry #1`, atau `flaky`, itu **bukan** bukti hijau.
- Kalau ada test di-skip (`-`), sebutkan nama test dan alasannya. Skip tanpa alasan = verifikasi tidak sah.

Yang **tidak** dihitung bukti:
- "sudah dites", "hijau", "lulus semua" tanpa blok output.
- Screenshot, video, atau trace tanpa perintah dan output teks.
- Ringkasan buatan sendiri ("21/22 lulus, sisanya aman").
- Output dari sesi, commit, atau mesin lain.
- Output yang diedit/diringkas sampai baris kegagalan hilang.

### 11.3 Cara membuktikan kegagalan itu bawaan (bukan akibat perubahan kamu)

Dilarang menulis "gagal bawaan" tanpa bukti. Untuk setiap kegagalan yang kamu klaim di luar scope, sertakan **ketiganya**:

1. Perintah persis yang dijalankan dan output mentah kegagalannya (nama spec, baris, assertion yang gagal).
2. Hasil `npx playwright test e2e/<spec>.spec.ts` **sendirian** di DB yang baru di-reset (bukan di tengah suite penuh).
3. Sebab konkret yang bisa dicek orang lain: tunjuk baris `supabase/seed.sql`, `e2e/helpers.ts`, atau commit yang memperkenalkannya (`git log -S "<teks assertion>"`). "Sepertinya memang begitu dari dulu" bukan bukti.

Kalau ketiganya tidak bisa dipenuhi, perlakukan sebagai **kegagalan task kamu**: perbaiki atau nyatakan task `terblokir`, jangan `selesai`.

Klasifikasi wajib saat ada kegagalan:

| Kondisi | Artinya | Yang wajib dilakukan |
| --- | --- | --- |
| Spec area gagal | Regresi task | Perbaiki kode/spec, ulangi A–F |
| Suite penuh gagal, spec area hijau | Interaksi state / regresi area lain | Cari spec yang saling merusak, perbaiki, jangan diabaikan |
| Lulus hanya di retry (`flaky`) | Gagal | Perbaiki akar masalah (race/async), bukan menambah retry |
| Gagal di DB bersih, lulus di DB kotor | Spec tidak mandiri | Perbaiki setup/cleanup spec |
| Gagal + bukti 11.3 lengkap | Di luar scope | Laporkan `sebagian`/`terblokir`, jangan `selesai` |

"Suite penuh merah tapi spec saya hijau" **bukan** alasan untuk selesai. Itu justru tanda ada regresi yang belum ketemu.

### 11.4 Larangan saat tes merah

- Dilarang menghapus, melewati (`test.skip`, `test.fixme`), mengganti nama, atau mengomentari tes yang gagal supaya hijau.
- Dilarang memakai `test.only` / `describe.only` untuk "mempersempit" suite, lalu mengklaim suite penuh hijau.
- Dilarang memperlonggar assertion (mis. `toHaveURL("/")` → `toHaveURL(/.*/)`, `expect(...).toBeTruthy()` menggantikan cek nilai, menghapus cek angka/status).
- Dilarang menaikkan timeout sebagai solusi utama. Timeout >10 detik harus disertai alasan teknis di komentar (mis. menunggu server action/pricing), bukan untuk menutupi race.
- Dilarang menambah `waitForTimeout` (sleep) sebagai pengganti web-first assertion, kecuali benar-benar tidak ada sinyal UI dan dijelaskan di komentar + laporan.
- Dilarang mengubah seed utama, data demo, atau konstanta bisnis hanya supaya tes lulus. Kalau seed memang salah, perbaiki di task yang sama dan jelaskan sebabnya.
- Dilarang menghapus langkah di dalam spec (mis. melewati `ensureShift`, `closeShift`, pembuatan data) untuk menghindari error.
- Dilarang mengubah `playwright.config.ts` (workers, retries, timeout global, testDir) untuk mengakali hasil, kecuali task-nya memang tentang konfigurasi.
- Dilarang meng-commit artefak `test-results/`, `playwright-report/`, trace, atau video.
- Kalau tes gagal karena bug aplikasi: perbaiki aplikasinya, bukan tesnya. Kalau ekspektasi tes yang usang: perbaiki tesnya sambil menjelaskan di laporan mengapa ekspektasi lama salah (bukan sekadar "disesuaikan").

Pelanggaran salah satu poin di atas = verifikasi **tidak sah**, walaupun semua tes kebetulan hijau.

### 11.5 Aturan menulis spec baru / mengubah spec

- Login **wajib** lewat `helpers.login(page)`. Jangan menyalin isi login ke spec.
- Jangan assert `toHaveURL("/")`: `/` selalu redirect ke `/(bengkel|toko)`. Pakai pola regex.
- Data uji wajib unik per run (`Date.now()` / `crypto.randomUUID()` di luar render React) supaya tidak bentrok dengan sisa run sebelumnya.
- Satu spec harus bisa lulus **sendirian** di DB bersih. Jangan bergantung pada spec lain yang jalan lebih dulu, pada shift yang kebetulan masih terbuka, atau pada stok yang kebetulan tersisa.
- Bersihkan state yang kamu buka sendiri (`closeShift` bila spec membuka shift) agar suite penuh tidak saling merusak. Kalau assert bisa gagal, cleanup tetap harus jalan (`try/finally`).
- Untuk alur yang menyentuh stok/uang, assert **nilai** yang terlihat user (total rupiah, status, sisa stok), bukan sekadar "halaman terbuka".
- Gunakan web-first assertion (`await expect(locator)...`), bukan `waitForTimeout`. Kalau menunggu proses server (mis. pricing), tunggu **efeknya** (tombol aktif, teks berubah), bukan durasi.
- Locator harus spesifik. Kalau nama muncul di nav dan kartu dashboard, pakai `exact: true` atau scope ke `getByRole("navigation")`.
- Satu spec = satu alur utama. Jangan menumpuk 5 skenario berbeda sampai kegagalan sulit dilacak.
- Kalau area baru belum punya spec, **wajib** buat spec untuk alur utamanya di task yang sama, lalu jalankan sesuai 11.1.
- Jangan menyalin helper ke dalam spec. Tambahkan helper bersama di `e2e/helpers.ts` bila dipakai lebih dari satu spec.

### 11.6 Baseline E2E (diperbarui 28 Okt 2026)

Baseline terakhir: `npm run e2e` di DB baru di-reset → **22 passed, 0 failed, 0 flaky**. Kegagalan di luar baseline ini adalah **regresi** dan wajib diselidiki, bukan langsung dicap "bawaan".

Spec yang dulu basi sudah diperbaiki (branch `chore/T-e2e-baseline`):

| Spec | Perbaikan |
| --- | --- |
| `e2e/stock.spec.ts` | Tidak lagi mengandalkan stok Semen dari seed. Spec menyetel stok minimum sendiri lewat `setProductMinStock`, lalu memulihkannya di `finally`. |
| `e2e/low-stock.spec.ts` | Sama; banner "Stok menipis" juga dipulihkan di dashboard bengkel & toko. |
| `e2e/catalog.spec.ts` | Link "Katalog" dipulihkan di navigasi (regresi `ca59927`), login lewat helper. |
| `e2e/auth-staff.spec.ts` | Assert `toHaveURL("/")` diganti pola `/(bengkel|toko)$/`, login lewat helper. |

Setelah perapian lanjutan, **semua spec login lewat `helpers.login(page)`** dan tidak ada lagi assert `toHaveURL("/")` setelah login. `pwa.spec.ts` hanya membuka `/login` untuk membaca manifest, itu bukan login. Jangan mengembalikan pola assert `"/"`.

### 11.7 Checklist verifikasi (salin ke laporan)

Sebelum menulis `STATUS: selesai`, jawab semua dengan bukti:

- [ ] A. `npm run lint` exit 0 (tempel output).
- [ ] A. `npm run typecheck` exit 0 (tempel output).
- [ ] A. `npm run test` hijau (tempel `Test Files ... / Tests ...`).
- [ ] B. `npm run db:reset` dijalankan setelah perubahan migrasi/kode terakhir (tempel output).
- [ ] C. `supabase test db` → `Result: PASS` (tempel `Files=..., Tests=...`).
- [ ] D. Spec area terkait lulus **sendirian** di DB bersih (tempel output + nama spec).
- [ ] E. DB di-reset lagi sebelum suite penuh (tempel output).
- [ ] F. `npm run e2e` → `0 failed`, `0 flaky` (tempel output lengkap/ringkasan sah).
- [ ] Semua kegagalan yang terlihat sudah diperbaiki, atau dibuktikan bawaan dengan 3 bukti 11.3.
- [ ] Tidak ada assertion yang diperlonggar, tes dihapus/di-skip, `test.only`, atau config Playwright yang diakali.
- [ ] Diff hanya berisi file yang relevan; tidak ada secret, `.env*`, `console.log` debug, atau artefak tes.
- [ ] Migrasi baru bernomor urut dan `src/lib/supabase/types.ts` sudah di-generate ulang bila skema berubah.
- [ ] Laporan memakai format Bagian 7 dan menempel output asli.

Template blok verifikasi di laporan:

```
VERIFIKASI (output mentah):

LINT:
<output>

TYPECHECK:
<output>

VITEST:
<output>

DB RESET:
<output>

PGTAP:
<output>

E2E TERKAIT:
<output>

E2E PENUH:
<output>
```

### 11.8 Audit sebelum commit (wajib)

Jalankan dan periksa semuanya:

```bash
git status --short          # hanya file yang kamu maksud
git diff --stat             # tidak ada file tak terduga
git diff                    # baca perubahan sendiri, jangan asal add -A
git diff --cached           # periksa yang akan di-commit
```

Yang wajib dipastikan:
- Tidak ada `.env*`, key, token, service role, atau kredensial di diff.
- Tidak ada `console.log`, `debugger`, komentar kode mati, atau `TODO` sementara.
- Tidak ada `test.skip`, `test.only`, `describe.only`, atau perubahan `playwright.config.ts` yang tidak dijelaskan.
- Tidak ada `test-results/`, `playwright-report/`, `trace.zip`, atau video ikut ter-stage.
- Tidak ada file di luar scope task (mis. `tmp/`, dokumen lain, refactor tak diminta). Kalau ada, keluarkan dari commit dan catat di laporan.
- Kalau skema berubah: migrasi baru + tes pgTAP + `src/lib/supabase/types.ts` hasil generate ikut di commit yang sama/berurutan.
- Kalau kode berubah setelah verifikasi terakhir: **ulangi langkah B–F**. Commit setelah verifikasi tidak otomatis membatalkan bukti hanya jika isi kode identik.

### 11.9 Konsekuensi

- Verifikasi yang tidak lengkap atau klaim tanpa output membuat laporan **tidak sah**; task dianggap belum selesai dan harus dibuka lagi.
- `flaky`, `skipped`, `test.only`, atau suite penuh merah **tidak boleh** dilaporkan sebagai `selesai`.
- Kalau ragu antara "mungkin aman" dan "sudah dijalankan": jalankan. Beberapa menit untuk suite penuh lebih murah daripada regresi yang lolos ke `main`.
- Aturan di Bagian 11 tidak boleh dilemahkan, diringkas, atau dilewati oleh agent mana pun. Perubahan aturan ini harus disetujui Ardi.

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
