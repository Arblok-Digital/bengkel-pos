import { test, expect } from "@playwright/test";

test("owner mengimpor produk dari CSV", async ({ page }) => {
  const suffix = Date.now().toString().slice(-6);
  const name1 = `Impor Barang ${suffix}`;
  const name2 = `Impor Jasa ${suffix}`;
  const csv = [
    "nama,sku,barcode,kategori,satuan,harga_jual,stok_minimum,jenis",
    `${name1},IMP-A-${suffix},,,pcs,12000,3,barang`,
    `${name2},IMP-B-${suffix},,,pcs,90000,0,jasa`,
  ].join("\n");

  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@bengkel.test");
  await page.getByLabel("Kata sandi").fill("bengkel123");
  await page.getByRole("button", { name: "Masuk" }).click();
  await expect(page).toHaveURL("/");

  await page.goto("/produk/impor");
  await page.getByLabel("Atau tempel isi CSV").fill(csv);
  await page.getByRole("button", { name: "Pratinjau" }).click();
  await expect(page.getByText("2 baris · 2 valid")).toBeVisible();

  await page.getByRole("button", { name: "Impor 2 produk" }).click();
  await expect(
    page.getByRole("status").filter({ hasText: "2 produk berhasil diimpor" })
  ).toBeVisible();

  await page.goto("/produk");
  await expect(page.getByRole("cell", { name: new RegExp(name1) })).toBeVisible();
  await expect(page.getByRole("cell", { name: new RegExp(name2) })).toBeVisible();
});
