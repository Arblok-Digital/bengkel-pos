import { test, expect } from "@playwright/test";

import { login } from "./helpers";

test("owner menyesuaikan stok dan melihat kartu stok", async ({ page }) => {
  const reason = `E2E koreksi ${Date.now().toString().slice(-6)}`;

  await login(page);

  await page.goto("/stok/sesuaikan");
  await page.getByLabel("Produk").selectOption({ label: "Oli Mesin 1L" });
  await page.getByLabel("Outlet").selectOption({ label: "Outlet Utama" });
  await page.getByLabel("Qty penyesuaian").fill("1");
  await page.getByLabel("Alasan").fill(reason);
  await page.getByRole("button", { name: "Simpan penyesuaian" }).click();
  await expect(page).toHaveURL("/stok");

  await page.getByRole("link", { name: "Oli Mesin 1L" }).click();
  await expect(page).toHaveURL(/\/stok\/.+/);
  await expect(page.getByText(reason)).toBeVisible();
});
