import { test, expect } from "@playwright/test";

import { login } from "./helpers";

test("owner menambah pelanggan dan pemasok", async ({ page }) => {
  const suffix = Date.now().toString().slice(-6);
  const customer = `Pelanggan ${suffix}`;
  const supplier = `Pemasok ${suffix}`;

  await login(page);

  await page.getByRole("link", { name: "Pelanggan", exact: true }).click();
  await expect(page).toHaveURL("/pelanggan");
  await page.getByLabel("Nama pelanggan").fill(customer);
  await page.getByLabel("Limit kredit (Rp)").fill("100000");
  await page.getByRole("button", { name: "Tambah pelanggan" }).click();
  await expect(page.getByRole("cell", { name: new RegExp(customer) })).toBeVisible();
  await expect(
    page.getByRole("row", { name: new RegExp(customer) })
  ).toContainText("Rp 100.000");

  await page.getByRole("link", { name: "Pemasok" }).click();
  await expect(page).toHaveURL("/pemasok");
  await page.getByLabel("Nama pemasok").fill(supplier);
  await page.getByLabel("Termin pembayaran (hari)").fill("14");
  await page.getByRole("button", { name: "Tambah pemasok" }).click();
  await expect(page.getByRole("cell", { name: new RegExp(supplier) })).toBeVisible();
  await expect(
    page.getByRole("row", { name: new RegExp(supplier) })
  ).toContainText("14 hari");
});
