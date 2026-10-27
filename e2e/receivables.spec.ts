import { expect, test } from "@playwright/test";
import { ensureShift, login } from "./helpers";

test("alur piutang: jual kredit -> cicil 2x -> lunas & kwitansi (T5.2)", async ({
  page,
}) => {
  test.slow();
  test.setTimeout(120_000);

  const suffix = Date.now().toString().slice(-5);
  const customerName = `Pelanggan Cicil ${suffix}`;

  await login(page);
  await ensureShift(page);

  // 1. Daftarkan pelanggan baru dengan limit kredit Rp 200.000
  await page.goto("/pelanggan");
  await page.getByLabel("Nama pelanggan").fill(customerName);
  await page.getByLabel("Limit kredit (Rp)").fill("200000");
  await page.getByRole("button", { name: "Tambah pelanggan" }).click();
  await expect(page.getByRole("cell", { name: customerName })).toBeVisible();

  // 2. Buka layar kasir & lakukan penjualan tempo
  await page.goto("/kasir");
  const search = page.getByPlaceholder(/Cari nama/);
  const payButton = page.getByRole("button", { name: "Bayar & simpan" });

  // Pilih pelanggan tempo
  await page.getByLabel("Pelanggan").selectOption({ label: customerName });

  // Tambahkan 1 sak Semen 40kg (Rp 65.000)
  await search.fill("Semen");
  await page.getByRole("button", { name: /Semen 40kg/ }).click();
  const semenQty = page.getByLabel("Qty Semen 40kg");
  await expect(semenQty).toBeVisible();

  // Metode pembayaran kredit/tempo
  await page.getByLabel("Metode pembayaran 1").selectOption("kredit_tempo");
  await expect(payButton).toBeEnabled({ timeout: 10_000 });

  // Simpan penjualan kredit
  await payButton.click();
  await expect(page.getByText(/Transaksi tersimpan: INV-/)).toBeVisible();
  await expect(page.getByText(/Sisa \(piutang\)/)).toBeVisible();

  // 3. Masuk ke halaman Daftar Piutang
  await page.goto("/piutang");
  await expect(page.getByRole("heading", { name: "Daftar Piutang Pelanggan" })).toBeVisible();

  // Cari baris pelanggan
  const row = page.locator("tr", { hasText: customerName });
  await expect(row).toBeVisible();
  await expect(row.getByTestId("receivable-status-badge")).toContainText("Belum Bayar");
  await expect(row.getByTestId("receivable-remaining")).toContainText("Rp 65.000");

  // 4. Buka halaman Detail Piutang
  await row.getByTestId("btn-detail-piutang").click();
  await expect(page).toHaveURL(/\/piutang\/[a-f0-9-]+$/);
  await expect(page.getByTestId("detail-remaining")).toContainText("Rp 65.000");
  await expect(page.getByTestId("detail-status-badge")).toContainText("Belum Bayar");

  // 5. Cicilan 1: Bayar Rp 25.000 tunai
  await page.getByTestId("input-pay-amount").fill("25000");
  await page.getByTestId("select-pay-method").selectOption("tunai");
  await page.getByTestId("btn-submit-payment").click();

  // Verifikasi saldo & status setelah Cicilan 1
  await expect(page.getByText(/Pembayaran berhasil dicatat/)).toBeVisible();
  await expect(page.getByTestId("detail-remaining")).toContainText("Rp 40.000");
  await expect(page.getByTestId("detail-status-badge")).toContainText("Sebagian");
  await expect(page.getByTestId("payment-row")).toHaveCount(1);
  await expect(page.getByTestId("payment-row").first()).toContainText("Rp 25.000");

  // 6. Verifikasi Kwitansi Cicilan 1
  await page.getByTestId("btn-view-kwitansi").click();
  await expect(page).toHaveURL(/\/piutang\/[a-f0-9-]+\/kwitansi/);
  await expect(page.getByRole("heading", { name: "Kwitansi Pembayaran" })).toBeVisible();
  await expect(page.getByTestId("kwitansi-amount")).toContainText("Rp 25.000");
  await expect(page.getByText(customerName).first()).toBeVisible();

  // Kembali ke detail piutang
  await page.getByRole("link", { name: /Kembali ke Detail Piutang/ }).click();
  await expect(page).toHaveURL(/\/piutang\/[a-f0-9-]+$/);

  // 7. Cicilan 2: Bayar pelunasan Rp 40.000 via transfer
  await expect(page.getByTestId("detail-remaining")).toContainText("Rp 40.000");
  await page.getByTestId("input-pay-amount").fill("40000");
  await page.getByTestId("select-pay-method").selectOption("transfer");
  await page.getByTestId("input-pay-reference").fill("TRF-CICIL-LUNAS");
  await page.getByTestId("btn-submit-payment").click();

  // Verifikasi saldo lunas
  await expect(page.getByTestId("detail-remaining")).toContainText("Rp 0");
  await expect(page.getByTestId("detail-status-badge")).toContainText("Lunas");
  await expect(page.getByText(/Piutang ini sudah lunas!/)).toBeVisible();
  await expect(page.getByTestId("payment-row")).toHaveCount(2);

  // 8. Verifikasi di Daftar Piutang
  await page.goto("/piutang");
  const finalRow = page.locator("tr", { hasText: customerName });
  await expect(finalRow).toBeVisible();
  await expect(finalRow.getByTestId("receivable-status-badge")).toContainText("Lunas");
  await expect(finalRow.getByTestId("receivable-remaining")).toContainText("Rp 0");
});
