import { test, expect } from "@playwright/test";

import { login } from "./helpers";

test("owner menambah kategori dan satuan", async ({ page }) => {
  const suffix = Date.now().toString().slice(-6);
  const category = `Kategori ${suffix}`;
  const unit = `satuan${suffix}`;

  await login(page);

  await page.getByRole("link", { name: "Katalog" }).click();
  await expect(page).toHaveURL("/katalog");

  await page.getByLabel("Nama kategori baru").fill(category);
  await page.getByRole("button", { name: "Tambah kategori" }).click();
  await expect(page.getByLabel(`Nama kategori ${category}`)).toBeVisible();

  await page.getByLabel("Nama satuan baru").fill(unit);
  await page.getByRole("button", { name: "Tambah satuan" }).click();
  await expect(page.getByLabel(`Nama satuan ${unit}`)).toBeVisible();
});
