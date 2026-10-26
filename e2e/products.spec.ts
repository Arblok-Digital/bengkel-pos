import { test, expect } from "@playwright/test";

test("owner menambah produk", async ({ page }) => {
  const suffix = Date.now().toString().slice(-6);
  const name = `Produk Uji ${suffix}`;

  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@bengkel.test");
  await page.getByLabel("Kata sandi").fill("bengkel123");
  await page.getByRole("button", { name: "Masuk" }).click();
  await expect(page).toHaveURL("/");

  await page.getByRole("link", { name: "Produk" }).click();
  await expect(page).toHaveURL("/produk");

  await page.getByLabel("Nama produk").fill(name);
  await page.getByLabel("Satuan").selectOption({ label: "pcs" });
  await page.getByLabel("Harga jual (Rp)").fill("15000");
  await page.getByLabel("Stok minimum").fill("1");
  await page.getByRole("button", { name: "Tambah produk" }).click();

  await expect(page.getByRole("cell", { name: new RegExp(name) })).toBeVisible();
  const row = page.getByRole("row", { name: new RegExp(name) });
  await expect(row).toContainText("Rp 15.000");
});
