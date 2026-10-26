import { test, expect } from "@playwright/test";

test("beranda tampil", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("h1")).toHaveText(
    "Kasir Bengkel & Toko Bangunan"
  );
});
