import { test, expect } from "@playwright/test";

import { closeShift, ensureShift, login } from "./helpers";

test("owner bisa retur sebagian dan void penjualan", async ({ page }) => {
  await login(page);
  await ensureShift(page);

  // Penjualan 1: 2 Oli untuk diretur sebagian.
  await page.getByPlaceholder(/Cari nama/).fill("Oli");
  await page.getByRole("button", { name: /Oli Mesin 1L/ }).click();
  await page.getByRole("button", { name: "Tambah Oli Mesin 1L" }).click();
  await expect(page.getByText("Rp 55.000 × 2 liter")).toBeVisible();
  await page.getByRole("button", { name: "Uang pas" }).click();
  await page.getByRole("button", { name: "Bayar & simpan" }).click();
  await expect(page.getByText(/Transaksi tersimpan: INV-/)).toBeVisible();

  // Retur 1 pcs dari penjualan terakhir.
  await page.goto("/penjualan");
  await page.getByRole("link", { name: "Detail" }).first().click();
  await page.getByLabel("Qty retur Oli Mesin 1L").fill("1");
  await page.getByLabel("Alasan retur").fill("Barang rusak");
  await page.getByRole("button", { name: "Simpan retur" }).click();
  await expect(page.getByText(/Retur tersimpan: Rp 55\.000/)).toBeVisible();
  await expect(page.getByText("Riwayat retur")).toBeVisible();
  await expect(page.getByText("Alasan: Barang rusak")).toBeVisible();

  // Penjualan 2: 1 Semen untuk di-void.
  await page.goto("/kasir");
  await page.getByPlaceholder(/Cari nama/).fill("Semen");
  await page.getByRole("button", { name: /Semen 40kg/ }).click();
  await page.getByRole("button", { name: "Uang pas" }).click();
  await page.getByRole("button", { name: "Bayar & simpan" }).click();
  await expect(page.getByText(/Transaksi tersimpan: INV-/)).toBeVisible();

  await page.goto("/penjualan");
  await page.getByRole("link", { name: "Detail" }).first().click();
  await page.getByLabel("Alasan void").fill("Salah input");
  await page.getByRole("button", { name: "Void penjualan" }).click();
  await expect(page.getByText("Alasan void: Salah input")).toBeVisible();

  await page.goto("/penjualan");
  await expect(page.locator("tbody tr").first()).toContainText("Void");

  await closeShift(page);
});
