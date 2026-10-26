import { test, expect } from "@playwright/test";

test("owner menambah pelanggan dan pemasok", async ({ page }) => {
  const suffix = Date.now().toString().slice(-6);
  const customer = `Pelanggan ${suffix}`;
  const supplier = `Pemasok ${suffix}`;

  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@bengkel.test");
  await page.getByLabel("Kata sandi").fill("bengkel123");
  await page.getByRole("button", { name: "Masuk" }).click();
  await expect(page).toHaveURL("/");

  await page.getByRole("link", { name: "Pelanggan" }).click();
  await expect(page).toHaveURL("/pelanggan");
  await page.getByLabel("Nama pelanggan").fill(customer);
  await page.getByLabel("Limit kredit (Rp)").fill("100000");
  await page.getByRole("button", { name: "Tambah pelanggan" }).click();
  await expect(page.getByRole("cell", { name: new RegExp(customer) })).toBeVisible();
  await expect(page.getByText("Rp 100.000")).toBeVisible();

  await page.getByRole("link", { name: "Pemasok" }).click();
  await expect(page).toHaveURL("/pemasok");
  await page.getByLabel("Nama pemasok").fill(supplier);
  await page.getByLabel("Termin pembayaran (hari)").fill("14");
  await page.getByRole("button", { name: "Tambah pemasok" }).click();
  await expect(page.getByRole("cell", { name: new RegExp(supplier) })).toBeVisible();
  await expect(page.getByText("14 hari")).toBeVisible();
});
