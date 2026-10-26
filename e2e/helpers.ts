import { expect, type Page } from "@playwright/test";

export async function login(page: Page) {
  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@bengkel.test");
  await page.getByLabel("Kata sandi").fill("bengkel123");
  await page.getByRole("button", { name: "Masuk" }).click();
  await expect(page).toHaveURL("/");
}

export async function ensureShift(page: Page) {
  await page.goto("/kasir");
  const gate = page.getByRole("link", { name: "Buka kasir / atur shift" });
  if ((await gate.count()) === 0) return;

  await gate.click();
  await expect(page).toHaveURL(/\/kasir\/shift/);
  await page.getByLabel("Modal awal (Rp)").fill("100000");
  await page.getByRole("button", { name: "Buka kasir" }).click();
  await expect(page).toHaveURL(/opened=1/);
  await page.goto("/kasir");
}

/** Tutup shift berjalan dengan kas seharusnya supaya selisih 0. */
export async function closeShift(page: Page) {
  await page.goto("/kasir/shift");
  const heading = page.getByRole("heading", { name: "Shift sedang berjalan" });
  if ((await heading.count()) === 0) return;

  const expectedText =
    (await page.locator('dt:has-text("Kas seharusnya") + dd').textContent()) ??
    "";
  const expected = expectedText.replace(/\D/g, "");

  await page.getByLabel("Uang tunai dihitung (Rp)").fill(expected);
  await page.getByRole("button", { name: "Tutup kasir" }).click();
  await expect(page).toHaveURL(/closed=1/);
}
