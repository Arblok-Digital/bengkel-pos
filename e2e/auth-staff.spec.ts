import { test, expect } from "@playwright/test";

test("owner mengelola staf, kasir tidak bisa membuka pengaturan", async ({
  page,
}) => {
  const staffEmail = `kasir.${Date.now()}@uji.test`;
  const staffPassword = "kasir12345";

  // Login sebagai owner (seed)
  await page.goto("/login");
  await page.getByLabel("Email").fill("admin@bengkel.test");
  await page.getByLabel("Kata sandi").fill("bengkel123");
  await page.getByRole("button", { name: "Masuk" }).click();
  await expect(page).toHaveURL("/");

  // Owner bisa membuka pengaturan
  await page.getByRole("link", { name: "Pengaturan" }).click();
  await expect(page).toHaveURL("/pengaturan");

  // Tambah staf baru
  await page.getByLabel("Email staf").fill(staffEmail);
  await page.getByLabel("Kata sandi sementara").fill(staffPassword);
  await page.locator('select[name="role"]').first().selectOption("kasir");
  await page.getByRole("button", { name: "Tambah staf" }).click();
  await expect(
    page.getByRole("status").filter({ hasText: "Staf ditambahkan" })
  ).toBeVisible();

  // Ubah peran staf
  const row = page.getByRole("row", { name: new RegExp(staffEmail) });
  await row.locator('select[name="role"]').selectOption("gudang");
  await row.getByRole("button", { name: "Simpan" }).click();
  await expect(
    row.getByRole("status").filter({ hasText: "Peran staf diperbarui" })
  ).toBeVisible();

  // Logout owner
  await page.getByRole("button", { name: "Keluar" }).click();
  await expect(page).toHaveURL("/login");

  // Login sebagai staf (gudang): tidak boleh melihat/membuka pengaturan
  await page.getByLabel("Email").fill(staffEmail);
  await page.getByLabel("Kata sandi").fill(staffPassword);
  await page.getByRole("button", { name: "Masuk" }).click();
  await expect(page).toHaveURL("/");

  await expect(page.getByRole("link", { name: "Pengaturan" })).toHaveCount(0);

  await page.goto("/pengaturan");
  await expect(page).toHaveURL("/");
});
