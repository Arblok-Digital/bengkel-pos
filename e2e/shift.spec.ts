import { test, expect, type Page } from "@playwright/test";

import { login } from "./helpers";

/** Tutup shift yang tertinggal dari percobaan sebelumnya agar tes idempoten. */
async function closeOpenShiftIfAny(page: Page) {
  const heading = page.getByRole("heading", { name: "Shift sedang berjalan" });
  if ((await heading.count()) === 0) return;

  const modal = page
    .locator("dt:has-text('Kas seharusnya') + dd")
    .first();
  const amount = ((await modal.textContent()) ?? "").replace(/\D/g, "");

  await page.getByLabel("Uang tunai dihitung (Rp)").fill(amount);
  await page.getByRole("button", { name: "Tutup kasir" }).click();
  await expect(page).toHaveURL(/closed=1/);
}

test("buka shift, tutup shift, selisih kas 0", async ({ page }) => {
  await login(page);

  await page.goto("/kasir/shift");
  await expect(page).toHaveURL("/kasir/shift");

  await closeOpenShiftIfAny(page);

  await page.getByLabel("Modal awal (Rp)").fill("300000");
  await page.getByRole("button", { name: "Buka kasir" }).click();
  await expect(page).toHaveURL(/opened=1/);

  await expect(
    page.getByRole("heading", { name: "Shift sedang berjalan" })
  ).toBeVisible();
  await expect(page.getByText("Rp 300.000").first()).toBeVisible();

  await page.getByLabel("Uang tunai dihitung (Rp)").fill("300000");
  await page.getByRole("button", { name: "Tutup kasir" }).click();
  await expect(page).toHaveURL(/closed=1/);

  await expect(
    page.getByRole("heading", { name: "Shift sedang berjalan" })
  ).toHaveCount(0);

  const row = page
    .getByRole("row")
    .filter({ hasText: "Tutup" })
    .filter({ hasText: "Rp 300.000" })
    .first();
  await expect(row).toBeVisible();
  await expect(row).toContainText("Rp 0");
});
