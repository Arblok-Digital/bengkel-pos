import { test, expect } from "@playwright/test";

import { login } from "./helpers";

test("badge dashboard membuka daftar stok menipis", async ({ page }) => {
  await login(page);

  const badge = page.getByRole("link", { name: /Stok menipis/ });
  await expect(badge).toBeVisible();
  await badge.click();

  await expect(page).toHaveURL("/stok/menipis");
  await expect(
    page.getByRole("heading", { name: "Stok Menipis" })
  ).toBeVisible();
  await expect(page.getByText(/produk di bawah stok minimum/)).toBeVisible();

  const row = page.getByRole("row", { name: /Semen 40kg/ });
  await expect(row).toBeVisible();
  // Qty ditandai merah (destructive) apa pun angka stoknya saat tes berjalan.
  await expect(row.locator("td").nth(3)).toHaveClass(/text-destructive/);
});
