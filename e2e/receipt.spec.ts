import { test, expect } from "@playwright/test";

import { closeShift, ensureShift, login } from "./helpers";

test("struk bisa dibuka, dicetak ulang, dan memakai footer pengaturan", async ({
  page,
}) => {
  await login(page);
  await ensureShift(page);

  // Jual 1 item supaya ada struk baru.
  await page.getByPlaceholder(/Cari nama/).fill("Oli");
  await page.getByRole("button", { name: /Oli Mesin 1L/ }).click();
  await page.getByRole("button", { name: "Uang pas" }).click();
  await page.getByRole("button", { name: "Bayar & simpan" }).click();
  await expect(page.getByText(/Transaksi tersimpan: INV-/)).toBeVisible();

  await page.getByRole("link", { name: "Lihat & cetak struk" }).click();
  await expect(page).toHaveURL(/\/struk\//);
  await expect(page.getByText(/INV-\d{8}-\d{4}/).first()).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Cetak struk" })
  ).toBeVisible();

  const wa = page.getByRole("link", { name: "Kirim WhatsApp" });
  await expect(wa).toHaveAttribute("href", /wa\.me\/.*text=/);

  await page.getByRole("button", { name: "80 mm" }).click();
  await expect(page.getByRole("button", { name: "80 mm" })).toBeVisible();

  // Pengaturan footer struk.
  await page.goto("/pengaturan");
  await page.getByLabel("Footer struk").fill("Garansi servis 7 hari");
  await page.getByRole("button", { name: "Simpan pengaturan struk" }).click();
  await expect(page.getByText("Pengaturan struk disimpan.")).toBeVisible();

  // Cetak ulang dari daftar penjualan harus memakai footer terbaru.
  await page.goto("/penjualan");
  await page.getByRole("link", { name: "Struk" }).first().click();
  await expect(page.getByText("Garansi servis 7 hari")).toBeVisible();

  await closeShift(page);
});
