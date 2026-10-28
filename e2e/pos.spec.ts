import { test, expect } from "@playwright/test";

import { login, ensureShift } from "./helpers";

test("jual barang dari layar kasir lalu tutup shift", async ({ page }) => {
  await login(page);
  await ensureShift(page);

  await expect(page.getByRole("heading", { name: "Kasir" })).toBeVisible();

  const search = page.getByPlaceholder(/Cari nama/);
  await search.fill("Oli");
  await page.getByRole("button", { name: /Oli Mesin 1L/ }).click();

  await expect(page.getByRole("heading", { name: "Keranjang" })).toBeVisible();
  await expect(page.getByText("Oli Mesin 1L").last()).toBeVisible();

  // Uang lebih: bayar 100.000, kembalian dihitung server.
  await page.getByRole("button", { name: "100.000", exact: true }).click();
  await page.getByRole("button", { name: "Bayar & simpan" }).click();

  await expect(page.getByText(/Transaksi tersimpan: INV-/)).toBeVisible();

  // Tutup shift: kas seharusnya = modal + tunai masuk, selisih harus 0.
  await page.goto("/kasir/shift");
  const expectedText =
    (await page.locator('dt:has-text("Kas seharusnya") + dd').textContent()) ??
    "";
  const expected = expectedText.replace(/\D/g, "");

  await page.getByLabel("Uang tunai dihitung (Rp)").fill(expected);
  await page.getByRole("button", { name: "Tutup kasir" }).click();
  await expect(page).toHaveURL(/closed=1/);

  const row = page
    .getByRole("row")
    .filter({ hasText: "Tutup" })
    .filter({ hasText: "Rp 0" })
    .first();
  await expect(row).toBeVisible();
});
