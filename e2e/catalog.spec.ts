import { test, expect } from "@playwright/test";

test("owner menambah kategori dan satuan", async ({ page }) => {
  const suffix = Date.now().toString().slice(-6);
  const category = `Kategori ${suffix}`;
  const unit = `satuan${suffix}`;

  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@bengkel.test");
  await page.getByLabel("Kata sandi").fill("bengkel123");
  await page.getByRole("button", { name: "Masuk" }).click();
  await expect(page).toHaveURL("/");

  await page.getByRole("link", { name: "Katalog" }).click();
  await expect(page).toHaveURL("/katalog");

  await page.getByLabel("Nama kategori baru").fill(category);
  await page.getByRole("button", { name: "Tambah kategori" }).click();
  await expect(page.getByLabel(`Nama kategori ${category}`)).toBeVisible();

  await page.getByLabel("Nama satuan baru").fill(unit);
  await page.getByRole("button", { name: "Tambah satuan" }).click();
  await expect(page.getByLabel(`Nama satuan ${unit}`)).toBeVisible();
});
