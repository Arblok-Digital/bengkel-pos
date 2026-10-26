import { test, expect } from "@playwright/test";

test("halaman stok menandai stok menipis", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@bengkel.test");
  await page.getByLabel("Kata sandi").fill("bengkel123");
  await page.getByRole("button", { name: "Masuk" }).click();
  await expect(page).toHaveURL("/");

  await page.getByRole("link", { name: "Stok", exact: true }).click();
  await expect(page).toHaveURL("/stok");

  const row = page.getByRole("row", { name: /Semen 40kg/ });
  await expect(row).toBeVisible();
  await expect(row).toContainText("Menipis");

  const aman = page.getByRole("row", { name: /Oli Mesin 1L/ });
  await expect(aman).toContainText("Aman");
});
