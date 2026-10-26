import { test, expect } from "@playwright/test";

test("badge dashboard membuka daftar stok menipis", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@bengkel.test");
  await page.getByLabel("Kata sandi").fill("bengkel123");
  await page.getByRole("button", { name: "Masuk" }).click();
  await expect(page).toHaveURL("/");

  const badge = page.getByRole("link", { name: /Stok menipis/ });
  await expect(badge).toBeVisible();
  await badge.click();

  await expect(page).toHaveURL("/stok/menipis");
  await expect(page.getByRole("heading", { name: "Stok Menipis" })).toBeVisible();

  const row = page.getByRole("row", { name: /Semen 40kg/ });
  await expect(row).toBeVisible();
  await expect(row).toContainText("5");
  await expect(row).toContainText("3");

  await expect(page.getByRole("row", { name: /Oli Mesin 1L/ })).toHaveCount(0);
});
