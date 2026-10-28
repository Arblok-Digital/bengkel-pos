import { test, expect } from "@playwright/test";

import { login } from "./helpers";

test("work order dibuat dari form lengkap", async ({ page }) => {
  const suffix = Date.now().toString().slice(-6);
  const customer = `Pelanggan WO ${suffix}`;
  const plate = `B ${suffix} WO`;

  await login(page);

  await page.goto("/pelanggan");
  await page.getByLabel("Nama pelanggan").fill(customer);
  await page.getByRole("button", { name: "Tambah pelanggan" }).click();
  await expect(page.getByRole("cell", { name: customer })).toBeVisible();

  await page.goto("/kendaraan");
  await page.getByLabel("Pelanggan").selectOption({ label: customer });
  await page.getByLabel("Nomor Polisi").fill(plate);
  await page.getByRole("button", { name: "Simpan Kendaraan" }).click();
  await expect(page.getByRole("cell", { name: plate })).toBeVisible();

  await page.goto("/bengkel/work-order");
  await page.getByLabel("Pelanggan").selectOption({ label: customer });
  await page.getByLabel("Kendaraan").selectOption({ label: plate });
  await page.getByLabel("Keluhan").fill("Servis berkala 10.000 km");

  await page.getByLabel("Produk item 1", { exact: true }).selectOption({ label: "Oli Mesin 1L" });
  await expect(page.getByLabel("Satuan item 1", { exact: true })).toHaveValue(/.+/);
  await page.getByLabel("Qty item 1", { exact: true }).fill("1");
  await expect(page.getByLabel("Harga satuan item 1", { exact: true })).toHaveValue("55000");

  await page.getByRole("button", { name: "Simpan Work Order" }).click();

  await expect(page).toHaveURL("/bengkel/work-order");
  const row = page.getByRole("row", { name: new RegExp(customer) });
  await expect(row).toBeVisible();
  await row.getByRole("link", { name: "Detail" }).click();

  await expect(page.getByRole("cell", { name: "Oli Mesin 1L" })).toBeVisible();
  await expect(page.getByText("Rp 55.000").first()).toBeVisible();
});
