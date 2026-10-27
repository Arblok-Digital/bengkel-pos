import { expect, test } from "@playwright/test";

import { ensureShift, login } from "./helpers";

test("penjualan kredit tempo dan validasi limit kredit pelanggan (T5.1)", async ({
  page,
}) => {
  test.slow();
  test.setTimeout(120_000);

  const suffix = Date.now().toString().slice(-5);
  const customerName = `Pelanggan Tempo ${suffix}`;

  await login(page);
  await ensureShift(page);

  // 1. Daftarkan pelanggan baru dengan limit kredit Rp 100.000
  await page.goto("/pelanggan");
  await page.getByLabel("Nama pelanggan").fill(customerName);
  await page.getByLabel("Limit kredit (Rp)").fill("100000");
  await page.getByRole("button", { name: "Tambah pelanggan" }).click();
  await expect(page.getByRole("cell", { name: customerName })).toBeVisible();

  // 2. Buka layar kasir
  await page.goto("/kasir");
  const search = page.getByPlaceholder(/Cari nama/);
  const payButton = page.getByRole("button", { name: "Bayar & simpan" });

  // Pilih pelanggan tempo
  await page.getByLabel("Pelanggan").selectOption({ label: customerName });

  // Masukkan 2 sak Semen (total = 130.000, melebihi limit kredit 100.000)
  await search.fill("Semen");
  await page.getByRole("button", { name: /Semen 40kg/ }).click();
  const semenQty = page.getByLabel("Qty Semen 40kg");
  await semenQty.fill("2");

  // Metode pembayaran kredit/tempo
  await page.getByLabel("Metode pembayaran 1").selectOption("kredit_tempo");

  // 3. Verifikasi validasi batas limit kredit di UI
  await expect(page.getByText(/melebihi limit/i)).toBeVisible();
  await expect(payButton).toBeDisabled();

  // 4. Ubah qty menjadi 1 sak (65.000 <= 100.000) -> batas aman
  await semenQty.fill("1");
  await expect(page.getByText(/melebihi limit/i)).toHaveCount(0);
  await expect(payButton).toBeEnabled({ timeout: 10_000 });

  // 5. Simpan transaksi kredit penuh (100% tempo, DP = 0)
  await payButton.click();
  await expect(page.getByText(/Transaksi tersimpan: INV-/)).toBeVisible();
  await expect(page.getByText(/Sisa \(piutang\)/)).toBeVisible();
  await expect(page.getByText("Rp 65.000").first()).toBeVisible();

  // 6. Verifikasi nota di daftar penjualan berstatus 'Kredit'
  await page.goto("/penjualan");
  const firstRow = page.locator("tbody tr").first();
  await expect(firstRow).toContainText("Kredit");
  await expect(firstRow).toContainText(customerName);

  // 7. Buka kasir lagi untuk transaksi parsial (DP tunai + sisa tempo)
  await page.goto("/kasir");
  await page.getByLabel("Pelanggan").selectOption({ label: customerName });
  await search.fill("Oli");
  await page.getByRole("button", { name: /Oli Mesin 1L/ }).click(); // 55.000

  // Bayar tunai 25.000, sisa 30.000 tempo (akumulasi piutang jadi 65.000 + 30.000 = 95.000 <= 100.000)
  await page.getByLabel("Nominal pembayaran 1").fill("25000");
  await expect(payButton).toBeEnabled();
  await payButton.click();

  await expect(page.getByText(/Transaksi tersimpan: INV-/)).toBeVisible();
  await expect(page.getByText("Rp 25.000").first()).toBeVisible(); // Dibayar
  await expect(page.getByText("Rp 30.000").first()).toBeVisible(); // Sisa piutang

  // 8. Verifikasi status transaksi parsial di daftar penjualan berstatus 'Sebagian'
  await page.goto("/penjualan");
  const partialRow = page.locator("tbody tr").first();
  await expect(partialRow).toContainText("Sebagian");
  await expect(partialRow).toContainText(customerName);

  // 9. Uji batas kumulatif server: coba transaksi lagi yang melebihi sisa limit
  // Piutang saat ini = 95.000 dari limit 100.000 (sisa plafon hanya 5.000)
  await page.goto("/kasir");
  await page.getByLabel("Pelanggan").selectOption({ label: customerName });
  await search.fill("Oli");
  await page.getByRole("button", { name: /Oli Mesin 1L/ }).click(); // 55.000
  await page.getByLabel("Nominal pembayaran 1").fill("10000"); // sisa 45.000 tempo -> 95.000 + 45.000 = 140.000 > 100.000
  await payButton.click();

  // Server menolak karena melebihi limit kredit kumulatif
  await expect(page.locator("p[role='alert']")).toContainText(
    /Melebihi limit kredit pelanggan/i
  );
});
