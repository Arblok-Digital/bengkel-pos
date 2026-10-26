import { test, expect } from "@playwright/test";

import { closeShift, ensureShift, login } from "./helpers";

test("pembayaran campuran, kembalian, dan hold transaksi", async ({ page }) => {
  await login(page);
  await ensureShift(page);

  // Jual 1 sak semen (65.000) dengan transfer 25.000 + tunai 50.000.
  await page.getByPlaceholder(/Cari nama/).fill("Semen");
  await page.getByRole("button", { name: /Semen 40kg/ }).click();

  await page.getByRole("button", { name: "+ Tambah pembayaran" }).click();
  await page.getByLabel("Metode pembayaran 2").selectOption("transfer");
  await page.getByLabel("Nominal pembayaran 1").fill("50000");
  await page.getByLabel("Nominal pembayaran 2").fill("25000");
  await page.getByLabel("Referensi pembayaran 2").fill("TRX-E2E");

  await expect(page.getByText("Kembalian")).toBeVisible();
  await expect(page.getByText("Rp 10.000").first()).toBeVisible();

  await page.getByRole("button", { name: "Bayar & simpan" }).click();
  await expect(page.getByText(/Transaksi tersimpan: INV-/)).toBeVisible();
  await expect(page.getByText("Rp 10.000").first()).toBeVisible();

  // Hold transaksi lalu lanjutkan lagi.
  await page.getByPlaceholder(/Cari nama/).fill("Oli");
  await page.getByRole("button", { name: /Oli Mesin 1L/ }).click();
  await page.getByRole("button", { name: "Tahan (F8)" }).click();
  await expect(page.getByText(/1 item/)).toBeVisible();

  await page.getByRole("button", { name: "Lanjutkan" }).click();
  await expect(page.getByLabel("Qty Oli Mesin 1L")).toHaveValue("1");

  await closeShift(page);
});
