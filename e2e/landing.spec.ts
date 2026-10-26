import { test, expect } from "@playwright/test";

test("tamu diarahkan ke halaman login", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveURL(/\/login$/);
  await expect(
    page.getByRole("heading", { name: "Kasir Bengkel & Toko Bangunan" })
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "Masuk" })).toBeVisible();
});
