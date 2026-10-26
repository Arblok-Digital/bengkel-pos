# ARCHITECTURE.md: Aplikasi Kasir Bengkel & Toko Bangunan

> Dokumen ini adalah sumber kebenaran tunggal untuk agent coding. Kerjakan **satu task per sesi**, sesuai urutan di Bagian 9. Jangan loncat fase. Jangan mengubah keputusan di Bagian 2 tanpa persetujuan Ardi.

---

## 1. Ringkasan Produk

Satu aplikasi web (PWA) untuk dua tipe usaha, dipilih per tenant:

| Mode | Kebutuhan khas |
|---|---|
| **Bengkel** | Servis kendaraan, work order (WO), mekanik, riwayat servis per kendaraan, sparepart + jasa dalam satu nota, pengingat servis berikutnya |
| **Toko bangunan** | Satuan bertingkat (sak, kg, batang, dus, m), harga per tipe pelanggan (umum, langganan, kontraktor), penjualan kredit/tempo, surat jalan/pengiriman, penawaran |
| **Inti bersama** | Kasir/POS, stok, pembelian ke supplier, piutang, shift kasir, laporan, cetak struk |

Prinsip UX utama: kasir bisa menyelesaikan transaksi umum dalam **maksimal 3 aksi**, bisa dipakai tablet/HP/laptop, tetap jalan saat internet putus.

Target pengguna: pemilik UMKM, kasir, mekanik, admin gudang. Bahasa UI: **Indonesia**.

---

## 2. Keputusan Teknis (Terkunci)

| Area | Keputusan | Alasan |
|---|---|---|
| Framework | Next.js 16 (App Router) + TypeScript strict | Satu codebase fullstack |
| UI | Tailwind + shadcn/ui + lucide-react | Cepat, konsisten, touch-friendly |
| Database | Supabase Postgres | RLS bawaan, auth, murah |
| Auth | Supabase Auth (email+password; PIN kasir fase lanjut) | Sederhana |
| Multi-tenant | Kolom `tenant_id` di **semua** tabel bisnis + RLS | Murah sekarang, mahal kalau ditambah belakangan |
| Validasi | Zod (satu schema dipakai client + server) | Hindari drift |
| Data fetching | TanStack Query + Server Actions untuk mutasi sederhana, **RPC Postgres** untuk mutasi atomik | Transaksi penjualan harus atomik |
| Offline | PWA (Serwist) + Dexie (IndexedDB) + antrean sync | Internet toko sering putus |
| Uang | **Integer rupiah (bigint)**, tidak pernah float | Hindari bug pembulatan |
| ID | UUID v7 dibuat **di client** untuk dokumen transaksi | Wajib untuk offline + idempotensi |
| Waktu | Simpan `timestamptz` UTC, tampilkan Asia/Jakarta | Konsisten |
| Cetak struk | `window.print()` dengan CSS 58/80mm dulu; ESC/POS via Web Bluetooth/WebUSB fase akhir | Bisa jalan tanpa driver |
| Deploy | Vercel (app) + Supabase (DB) | Sudah dikuasai |
| Test | Vitest (unit), Playwright (e2e alur kasir), pgTAP/SQL test untuk RPC & RLS | Alur uang harus teruji |

**Aturan uang & stok (tidak boleh dilanggar):**
1. Stok **tidak pernah di-update langsung**. Semua perubahan lewat tabel append-only `stock_movements`; `stock_levels` hanya cache hasil trigger.
2. Penjualan, penerimaan barang, retur, dan penyesuaian stok dilakukan dalam **satu transaksi DB** (fungsi RPC).
3. Dokumen yang sudah `paid`/`posted` tidak boleh diedit; koreksi lewat retur atau void dengan alasan + audit log.
4. Harga jual dan HPP **disalin ke baris item** saat transaksi (snapshot), bukan dirujuk ke produk.

---

## 3. Struktur Repo

```
/
├─ ARCHITECTURE.md
├─ AGENTS.md                 # aturan untuk agent (salin dari Bagian 10)
├─ supabase/
│  ├─ migrations/            # SQL bernomor, satu perubahan per file
│  ├─ seed.sql
│  └─ tests/                 # pgTAP: RLS + RPC
├─ src/
│  ├─ app/
│  │  ├─ (auth)/login
│  │  ├─ (app)/
│  │  │  ├─ kasir/           # layar POS
│  │  │  ├─ bengkel/         # work-order, kendaraan, mekanik
│  │  │  ├─ produk/
│  │  │  ├─ stok/
│  │  │  ├─ pembelian/
│  │  │  ├─ pelanggan/
│  │  │  ├─ piutang/
│  │  │  ├─ pengiriman/      # surat jalan
│  │  │  ├─ laporan/
│  │  │  └─ pengaturan/
│  │  └─ api/                # hanya untuk webhook/cron
│  ├─ features/              # logika per domain (components, hooks, schema, queries)
│  │  ├─ pos/ inventory/ catalog/ customers/ workorder/ purchasing/ ar/ delivery/ reports/
│  ├─ lib/
│  │  ├─ supabase/           # client, server, types (generated)
│  │  ├─ money.ts            # format & hitung rupiah (integer)
│  │  ├─ offline/            # dexie db, sync queue
│  │  └─ print/              # template struk
│  └─ components/ui/         # shadcn
└─ e2e/                      # playwright
```

Aturan: komponen halaman tipis, logika di `features/<domain>`. Tidak ada query Supabase langsung di komponen UI; lewat fungsi di `features/*/queries.ts`.

---

## 4. Model Data

Semua tabel punya: `id uuid pk`, `tenant_id uuid not null`, `created_at`, `updated_at`, `created_by`. Tabel transaksi juga punya `outlet_id`. Singkat ditulis di bawah hanya kolom pentingnya.

### 4.1 Tenant & akses
- `tenants`: `name`, `business_type` (`bengkel` | `toko_bangunan` | `both`), `settings jsonb` (nama struk, footer, pajak, dll.)
- `outlets`: `tenant_id`, `name`, `address`, `phone`
- `memberships`: `tenant_id`, `user_id`, `role` (`owner` | `admin` | `kasir` | `mekanik` | `gudang` | `dev`), `outlet_ids uuid[]`, `active`. `dev` adalah role operator platform: aktif di satu tenant mana pun memberi akses baca/tulis lintas tenant. **Hanya operator (SQL/service role) yang boleh membuat dev pertama; owner/admin tenant tidak boleh memberi, mengubah, atau menghapus role `dev`** (ditegakkan di policy `0005`).
- `audit_logs`: `entity`, `entity_id`, `action`, `before jsonb`, `after jsonb`, `reason`, `user_id`

### 4.2 Katalog
- `categories`: `name`, `parent_id`
- `units`: `name` (pcs, sak, kg, batang, dus, liter, meter, set)
- `products`: `sku`, `barcode`, `name`, `category_id`, `kind` (`barang` | `jasa` | `paket`), `base_unit_id`, `track_stock bool`, `cost_price bigint`, `sell_price bigint`, `min_stock numeric`, `active`
- `product_units`: `product_id`, `unit_id`, `factor_to_base numeric` (1 sak = 40 kg), `sell_price bigint`, `barcode`
- `price_tiers`: `name` (umum, langganan, kontraktor, bengkel-partner)
- `product_prices`: `product_id`, `tier_id`, `unit_id`, `price bigint`
- `price_breaks`: `product_id`, `unit_id`, `min_qty numeric`, `price bigint` (harga grosir berdasarkan jumlah beli; dihitung setelah tier, ambil harga terendah yang berlaku)
- `bundle_items`: untuk `kind = paket` (misal "Servis berkala" = jasa + oli + filter)

### 4.3 Stok
- `stock_movements` (append-only): `product_id`, `outlet_id`, `qty_base numeric` (+masuk / −keluar), `type` (`purchase` | `sale` | `sale_return` | `adjustment` | `opname` | `transfer_in` | `transfer_out` | `workorder_use`), `ref_type`, `ref_id`, `unit_cost bigint`, `note`
- `stock_levels`: `(product_id, outlet_id)` unik, `qty_base`, diisi trigger dari `stock_movements`
- `stock_opnames` + `stock_opname_items`: hitung fisik vs sistem, selisih jadi movement `opname`

### 4.4 Pelanggan & kendaraan
- `customers`: `name`, `phone`, `address`, `tier_id`, `credit_limit bigint`, `notes`
- `vehicles` (bengkel): `customer_id`, `plate_no`, `brand`, `model`, `year`, `vin`, `last_odometer`
- `suppliers`: `name`, `phone`, `address`, `payment_terms_days`

### 4.5 Penjualan
- `sales`: `invoice_no` (per outlet per hari, sequence), `client_uuid` (idempotensi), `customer_id`, `vehicle_id?`, `work_order_id?`, `status` (`draft` | `paid` | `partial` | `credit` | `void`), `subtotal`, `discount`, `tax`, `total`, `paid_amount`, `cashier_id`, `shift_id`, `sold_at`
- `sale_items`: `sale_id`, `product_id`, `unit_id`, `qty`, `qty_base`, `unit_price`, `unit_cost` (snapshot HPP), `discount`, `line_total`, `note` (catatan per item, tampil di struk), `mechanic_id?`
- `payments`: `sale_id`, `method` (`tunai` | `transfer` | `qris` | `debit` | `kredit_tempo`), `amount`, `reference`
- `sale_returns` + `sale_return_items`

### 4.6 Piutang
- `receivables`: `sale_id`, `customer_id`, `amount`, `due_date`, `status` (`open` | `partial` | `paid`)
- `receivable_payments`: `receivable_id`, `amount`, `method`, `paid_at`

### 4.7 Pembelian
- `purchase_orders`: `supplier_id`, `status` (`draft` | `ordered` | `partial` | `received` | `cancelled`), `total`
- `purchase_order_items`
- `goods_receipts` + `goods_receipt_items`: saat posting → movement `purchase` + update HPP (metode **rata-rata bergerak**)
- `payables` (hutang supplier): versi sederhana, mirror piutang

### 4.8 Bengkel
- `work_orders`: `wo_no`, `queue_no` (nomor antrean, reset tiap hari per outlet), `customer_id`, `vehicle_id`, `odometer`, `complaint`, `diagnosis`, `status` (`antri` | `dikerjakan` | `menunggu_part` | `selesai` | `ditagih` | `dibatalkan`), `mechanic_id`, `estimate_total`, `sale_id?`
- `work_order_items`: jasa & sparepart, `qty`, `unit_price`
- `service_reminders`: `vehicle_id`, `next_date`, `next_odometer`, `message`, `sent_at`
- Komisi mekanik: dihitung dari `sale_items.mechanic_id` + `settings.commission_pct`

### 4.9 Toko bangunan
- `quotations` + `quotation_items`: penawaran → bisa dikonversi jadi `sales`
- `deliveries`: `sale_id`, `delivery_no` (surat jalan), `address`, `driver`, `vehicle_plate`, `status` (`disiapkan` | `dikirim` | `diterima`)
- `delivery_items`: mendukung pengiriman bertahap (sebagian barang)

### 4.10 Kas
- `cash_shifts`: `cashier_id`, `outlet_id`, `opened_at`, `opening_cash`, `closed_at`, `closing_cash_counted`, `expected_cash`, `difference`
- `expenses`: biaya operasional harian, `category`, `amount`, `shift_id?`

### 4.11 Pola RLS (wajib di setiap tabel)

```sql
create function public.is_member(t uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships m
    where m.tenant_id = t and m.user_id = auth.uid() and m.active
  )
$$;

-- Baca: untuk semua member tenant
alter table products enable row level security;
create policy products_select_member on products for select to authenticated
  using (public.is_member(tenant_id));

-- Tulis: per perintah, hanya owner/admin. Tenant tidak boleh di-hard-delete
-- lewat API (tanpa policy delete); pembuatan tenant lewat RPC onboarding.
create policy products_insert_admin on products for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy products_update_admin on products for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));
-- DELETE hanya jika memang diizinkan desain; kalau tidak, jangan buat policy DELETE.
```

Pembatasan role (misal `kasir` tidak boleh ubah `cost_price`) dilakukan lewat fungsi `public.has_role(tenant_id, roles[])` di policy tulis per perintah, bukan di UI saja. Tabel baru wajib punya pasangan tes pgTAP positif (boleh oleh role yang berhak) dan negatif (ditolak untuk role lain); setiap tes negatif diikuti verifikasi sebagai postgres bahwa data tidak berubah.

**`tenant_id` tidak boleh berpindah lewat UPDATE.** Policy `WITH CHECK` hanya melihat baris baru, jadi user yang admin/owner di dua tenant bisa memindahkan baris antar-tenant. Setiap tabel ber-`tenant_id` wajib memasang trigger yang sama (contoh di migrasi `0003`), dan tesnya memakai aktor yang owner di dua tenant:

```sql
create trigger products_tenant_id_immutable before update on products
  for each row execute function public.prevent_tenant_change();
```

`set_created_by` memaksa `created_by = auth.uid()` saat ada sesi user (nilai kiriman client diabaikan); tanpa sesi (server/service) nilai eksplisit dihormati. Helper `is_member`/`has_role` dan trigger `protect_last_owner` wajib `security definer` supaya tidak bergantung pada policy SELECT dan tidak rekursif.

**Role `dev` (operator platform).** `public.is_dev()` bernilai true bila user punya membership aktif ber-role `dev` di tenant mana pun; policy `tenants`/`outlets`/`memberships` memberi `or public.is_dev()` pada baca dan tulis. Karena itu role `dev` **tidak boleh** bisa diberikan lewat API tenant: policy `memberships` di `0005` mensyaratkan `role <> 'dev' or public.is_dev()` pada INSERT/UPDATE/DELETE. Dev pertama dibuat lewat SQL/service role. Tes wajib memuat negatif "owner/admin tidak bisa memberi role dev" dan "dev nonaktif kehilangan akses global".

**HPP/modal disembunyikan dari kasir.** Role `kasir` dan `mekanik` tidak boleh membaca `cost_price`, `unit_cost`, atau nilai aset stok. Sediakan view `products_pos` (tanpa kolom biaya) untuk layar kasir dan daftar stok, dan cabut akses baca tabel `products` untuk dua role itu. Menyembunyikan di UI saja tidak cukup.

---

## 5. Alur Kritis

### 5.1 Penjualan (RPC `create_sale`)
Input: `client_uuid`, outlet, customer?, items[], payments[], shift_id, work_order_id?.
Dalam **satu transaksi**:
1. Cek idempotensi: jika `client_uuid` sudah ada, kembalikan sale yang sama.
2. Validasi stok (tolak jika minus, kecuali `settings.allow_negative_stock`).
3. Hitung ulang total di server dari harga yang dikirim + verifikasi terhadap tier (jangan percaya total dari client).
4. Insert `sales`, `sale_items` (snapshot harga + HPP), `payments`.
5. Insert `stock_movements` (`sale`) per item `track_stock`.
6. Jika `paid_amount < total`: buat `receivables`, validasi `credit_limit`.
7. Jika dari WO: set status WO `ditagih`.
8. Tulis `audit_logs`. Return `sale_id` + `invoice_no`.

### 5.2 Work order bengkel
`antri → dikerjakan → (menunggu_part) → selesai → ditagih`. Pemakaian sparepart di WO belum memotong stok; stok terpotong saat WO dikonversi jadi sale (satu jalur potong stok, tidak ada dobel).

### 5.3 Penerimaan barang
Posting `goods_receipt` → movement `purchase` → hitung ulang HPP rata-rata bergerak → update `payables`.

### 5.4 Tutup shift
`expected_cash = opening_cash + tunai masuk − tunai keluar (expenses)`. Selisih disimpan, tidak dikoreksi diam-diam.

---

## 6. Desain UI/UX

**Layar Kasir (paling penting):**
- Layout dua kolom di tablet/laptop: kiri pencarian + grid produk, kanan keranjang. Di HP: keranjang jadi bottom sheet.
- Pencarian satu kolom: nama, SKU, barcode, plat nomor (mode bengkel). Hasil muncul saat mengetik (debounce ≤150 ms, dari cache lokal).
- Scan barcode via input fokus otomatis (scanner USB = keyboard) dan kamera sebagai opsi.
- Tombol minimal 44 px, angka besar, kontras tinggi.
- Shortcut: `F2` cari, `F4` bayar, `F8` tahan transaksi, `Esc` batal, `Enter` konfirmasi.
- Bayar: tombol nominal cepat (uang pas, 50rb, 100rb), kembalian otomatis besar di layar.
- Ganti satuan per baris (sak ↔ kg) dengan satu tap; harga ikut tier pelanggan.
- Transaksi "ditahan" (hold) bisa banyak, tersimpan lokal.
- Catatan per item di keranjang (misal "oli merk X", "diantar sore").
- Stok menipis ditandai **merah + tebal** di semua daftar produk dan hasil pencarian kasir, bukan hanya di dashboard.
- Foto produk bisa diketuk untuk diperbesar (membedakan merk/tipe sparepart yang mirip).
- Daftar harga/stok untuk kasir tidak menampilkan modal (lihat Bagian 4.11).

**Prinsip umum:**
- Format `Rp 1.250.000`, tanggal `26 Okt 2026`, semua teks Bahasa Indonesia.
- Setiap form: validasi inline, pesan error manusiawi, tidak ada dialog konfirmasi yang tidak perlu (kecuali void/hapus).
- State kosong yang membantu ("Belum ada produk. Tambah produk pertama").
- Mode gelap opsional, mode terang default.
- Indikator status koneksi + jumlah transaksi menunggu sinkron, selalu terlihat di header kasir.
- Aksesibilitas: label jelas, fokus keyboard terlihat, jangan andalkan warna saja.

**Navigasi:** menu menyesuaikan `business_type` (modul bengkel disembunyikan untuk toko bangunan dan sebaliknya).

---

## 7. Offline & Sinkronisasi

- Yang disimpan lokal (Dexie): produk, harga, customer, kendaraan, stok terakhir, transaksi menunggu sinkron.
- Transaksi offline: dibuat di Dexie dengan `client_uuid`, masuk antrean `outbox`, dikirim ke `create_sale` saat online. Idempotensi mencegah dobel.
- Nomor invoice offline: pakai nomor sementara (`TMP-<device>-<seq>`), diganti nomor resmi setelah sinkron; struk offline menampilkan nomor sementara.
- Konflik stok: server menang. Jika stok tidak cukup saat sinkron, transaksi masuk status `needs_review` dan muncul di daftar yang harus diselesaikan pemilik, **tidak dibuang**.
- Offline bukan fitur tambahan, ini syarat dasar untuk pasar UMKM. Kerjakan **Fase 10 tepat setelah Fase 4**, sebelum piutang, pembelian, dan modul khusus. Dari Fase 0 semua ID dokumen harus UUID dari client dan semua RPC harus idempoten.
- Kebijakan per tenant: `settings.require_online_for_sale` (default `false`). Toko yang ingin stok selalu akurat bisa memaksa transaksi hanya saat online.

---

## 8. Non-Fungsional

- **Keamanan:** RLS di semua tabel, service role key hanya di server, tidak pernah di client. Validasi Zod di server untuk semua input.
- **Performa:** daftar besar pakai pagination/cursor; indeks di `(tenant_id, …)` untuk semua query umum; layar kasir tidak boleh menunggu jaringan untuk pencarian produk.
- **Backup:** Supabase daily backup + ekspor CSV laporan penting dari menu pengaturan.
- **Observability:** error boundary + log ke Sentry (atau Vercel logs di tahap awal).
- **Privasi data:** nomor HP pelanggan hanya terlihat role yang berhak.
- **Pajak:** MVP tanpa e-Faktur. Opsi PPN sebagai persentase di nota. Integrasi pajak resmi di luar scope.

---

## 9. Rencana Implementasi Bertahap

Format tiap task: **Tujuan → Pekerjaan → Selesai bila (acceptance criteria) → Verifikasi**. Satu task = satu sesi agent, dengan commit sendiri.

### Fase 0: Fondasi
**T0.1 Bootstrap repo**
- Pekerjaan: `create-next-app` (TS, Tailwind, App Router), pasang shadcn/ui, Zod, TanStack Query, Vitest, Playwright, ESLint + Prettier, struktur folder Bagian 3.
- Selesai bila: `npm run dev`, `npm run lint`, `npm run test` semua hijau; halaman beranda tampil.
- Verifikasi: jalankan ketiga perintah dan tempel output.

**T0.2 Supabase lokal + migrasi pertama**
- Pekerjaan: `supabase init`, `supabase start`, migrasi `0001_tenants_memberships.sql` (tenants, outlets, memberships, fungsi `is_member`, `has_role`), generate types ke `src/lib/supabase/types.ts`.
- Selesai bila: `supabase db reset` sukses; tes pgTAP membuktikan user tenant A tidak bisa baca data tenant B.

**T0.3 `lib/money.ts`**
- Pekerjaan: `formatRupiah`, `parseRupiah`, `mulQty` (qty desimal × harga integer dengan pembulatan terdefinisi), unit test lengkap.
- Selesai bila: ≥15 test termasuk kasus 0, negatif, desimal 0,5 sak, angka besar.

### Fase 1: Auth & Onboarding
**T1.1** Login/logout, middleware proteksi route `(app)`, sesi server.
**T1.2** Onboarding tenant: buat tenant + outlet pertama + membership `owner`, pilih `business_type`.
**T1.3** Manajemen pengguna: undang staf, ubah role, nonaktifkan. Menu & route dibatasi per role.
- Selesai bila: kasir tidak bisa membuka `/pengaturan` maupun memanggil aksi admin (uji sebagai kasir, bukan hanya sembunyikan menu).

### Fase 2: Master Data
**T2.1** Kategori & satuan (CRUD).
**T2.2** Produk (CRUD + upload gambar opsional + barcode). Form cepat: nama, satuan, harga, stok awal.
**T2.3** Konversi satuan (`product_units`) + tier harga (`price_tiers`, `product_prices`) + harga grosir per jumlah (`price_breaks`). UI tabel harga per tier.
**T2.4** Pelanggan (+ tier, limit kredit), supplier.
**T2.5** Impor produk dari CSV/Excel dengan pratinjau + laporan baris gagal.
- Selesai bila: 500 produk bisa diimpor, produk dengan 2 satuan menghitung harga benar di tier berbeda.

### Fase 3: Inventori
**T3.1** Migrasi `stock_movements` + trigger `stock_levels` + view stok per outlet.
**T3.2** Penyesuaian stok manual (wajib alasan) + riwayat kartu stok per produk.
**T3.3** Stok opname (hitung fisik → selisih → posting).
**T3.4** Daftar stok menipis (`< min_stock`) + badge di dashboard.
- Selesai bila: stok hanya berubah lewat movement; tes SQL membuktikan UPDATE langsung ke `stock_levels` oleh role biasa ditolak.

### Fase 4: Kasir (inti produk)
**T4.1** Shift: buka kasir (modal awal), tutup kasir (hitung selisih).
**T4.2** RPC `create_sale` lengkap sesuai 5.1 + tes SQL (idempoten, stok minus ditolak, total dihitung server).
**T4.3** UI Kasir: pencarian, keranjang, ubah qty/satuan/diskon, pelanggan opsional.
**T4.4** Pembayaran: tunai/transfer/QRIS manual/campuran, kembalian, hold transaksi.
**T4.5** Struk: template 58/80 mm, cetak, cetak ulang, simpan/bagikan sebagai gambar atau PDF, kirim via link WhatsApp (`wa.me`). Pengaturan struk: logo, nama, alamat, footer (info garansi/promo), opsi sembunyikan persen pajak, nama mekanik tampil di struk bengkel.
**T4.6** Void & retur (butuh role admin + alasan, membuat movement balik).
- Selesai bila: e2e Playwright "buka shift → jual 3 item beda satuan → bayar campuran → cetak → tutup shift" hijau dan selisih kas = 0.
- Catatan: alur shift, transaksi penjualan, dan piutang adalah area yang berulang muncul di daftar perbaikan bug kompetitor, jadi tes e2e untuk tiga alur ini wajib, bukan opsional.

### Fase 5: Piutang
**T5.1** Penjualan kredit/tempo dari kasir (cek limit).
**T5.2** Daftar piutang, jatuh tempo, pembayaran cicilan, kwitansi.
**T5.3** Pengingat tagihan via WhatsApp link + kartu piutang per pelanggan. Notifikasi dalam aplikasi untuk piutang mendekati/lewat jatuh tempo.
- Selesai bila: e2e "jual kredit → cicil 2x → lunas" hijau dan saldo piutang akurat di tiap langkah.

### Fase 6: Pembelian
**T6.1** PO ke supplier (draft → ordered).
**T6.2** Penerimaan barang (parsial) → stok + HPP rata-rata bergerak.
**T6.3** Hutang supplier + pembayaran.

### Fase 7: Modul Bengkel
**T7.1** Kendaraan (plat unik per tenant) + riwayat servis.
**T7.2** Work order: buat, nomor antrean harian, tambah jasa/sparepart, ubah status, tugaskan mekanik, cetak **SPK** (surat perintah kerja) untuk mekanik, kirim status servis ke pelanggan via link WhatsApp.
**T7.3** Konversi WO → penjualan (satu klik, lewat `create_sale`).
**T7.4** Paket servis (bundle) + estimasi biaya yang bisa dikirim ke pelanggan.
**T7.5** Pengingat servis berikutnya (tanggal/odometer) + laporan komisi mekanik.

### Fase 8: Modul Toko Bangunan
**T8.1** Penawaran (quotation) → konversi ke penjualan.
**T8.2** Surat jalan & pengiriman bertahap, cetak surat jalan.
**T8.3** Harga otomatis per tier saat pelanggan dipilih; peringatan jual di bawah HPP.

### Fase 9: Laporan & Dashboard
**T9.1** Dashboard: omzet hari ini, transaksi, produk terlaris, stok menipis, piutang jatuh tempo.
**T9.2** Laporan: penjualan per periode/kasir/produk/metode pembayaran, laba kotor (pakai HPP snapshot), kas harian, stok + nilai aset stok (total modal), piutang, hutang, komisi mekanik. Laporan bernilai modal hanya untuk role owner/admin.
**T9.3** Ekspor CSV/PDF.
- Selesai bila: laba kotor cocok dengan hitung manual di dataset seed.

### Fase 10: Offline PWA (kerjakan tepat setelah Fase 4, sebelum Fase 5)
**T10.1** Service worker + manifest + installable.
**T10.2** Cache katalog ke Dexie, pencarian kasir dari lokal.
**T10.3** Outbox + sinkron + status `needs_review`.
**T10.4** Tes e2e dengan network dimatikan di tengah transaksi.

### Fase 11: Hardening & Rilis
**T11.1** Audit log viewer, pembatasan role final, review semua policy RLS.
**T11.2** Perf pass: indeks, query lambat, bundle size layar kasir.
**T11.3** Cetak ESC/POS langsung (Web Bluetooth/USB) sebagai opsi, termasuk pemicu buka laci kas (cash drawer) dan cetak label barcode sparepart.
**T11.4** Deploy Vercel + Supabase produksi, env, backup, runbook singkat.
**T11.5** UAT dengan 1 bengkel dan 1 toko bangunan nyata; catat temuan.

---

## 10. Aturan untuk Agent (salin ke `AGENTS.md`)

1. Baca `ARCHITECTURE.md` dan kerjakan **hanya** task yang diminta. Jangan menambah fitur di luar acceptance criteria.
2. Setiap perubahan skema = file migrasi baru bernomor. Jangan edit migrasi lama yang sudah di-commit.
3. Jangan pernah pakai `float` untuk uang. Semua uang integer rupiah lewat `lib/money.ts`.
4. Jangan menulis `UPDATE stock_levels`. Stok hanya lewat `stock_movements`.
5. Setiap tabel baru: `tenant_id`, RLS aktif, policy `tenant_isolation`, indeks `(tenant_id, …)`.
6. Mutasi yang menyentuh uang/stok = RPC Postgres atomik + tes SQL, bukan beberapa panggilan dari client.
7. Sebelum bilang selesai: jalankan `npm run lint && npm run test` dan (jika menyentuh DB) `supabase db reset && supabase test db`. **Tempel output mentahnya.** Jangan klaim berhasil tanpa output.
8. Jika spesifikasi ambigu atau butuh keputusan di luar dokumen ini, **berhenti dan tanya**, jangan menebak.
9. Commit kecil dan sering, pesan commit format `feat(pos): ...`, `fix(stock): ...`.
10. Jangan install dependensi baru di luar Bagian 2 tanpa izin.

**Template prompt per task (tempel ke agent):**

```
Kerjakan task <ID> dari ARCHITECTURE.md Bagian 9.
Batasan: hanya task ini, patuhi Aturan Agent (Bagian 10).
Selesai bila: <salin acceptance criteria>.
Setelah selesai: jalankan verifikasi, tempel output mentah, lalu daftar file yang berubah.
```

---

## 11. Risiko & Catatan

| Risiko | Mitigasi |
|---|---|
| Stok selisih karena race condition dua kasir | RPC atomik + `SELECT … FOR UPDATE` pada `stock_levels` di dalam `create_sale` |
| Offline menyebabkan stok minus | Status `needs_review`, bukan tolak/hapus diam-diam |
| Satuan bertingkat membingungkan kasir | Selalu tampilkan satuan aktif + konversi di baris keranjang |
| Scope melebar (akuntansi penuh, e-Faktur, multi-gudang kompleks) | Di luar MVP; catat sebagai backlog |
| Agent model dengan konteks terbatas hilang arah | Task kecil (Bagian 9), satu sesi per task, selalu mulai dari `ARCHITECTURE.md` + `AGENTS.md` |

**Backlog pasca-MVP:** integrasi payment gateway (Midtrans/Xendit) untuk QRIS dinamis, multi-cabang + transfer stok antar outlet, loyalty/poin, integrasi akuntansi, aplikasi mekanik khusus (HP), notifikasi WhatsApp otomatis via API resmi.
