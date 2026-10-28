import { test, expect } from "@playwright/test";

import { login, setProductMinStock } from "./helpers";

test("halaman stok menandai stok menipis", async ({ page }) => {
  await login(page);

  // Seed menyisakan stok sehat (Semen 482, minimum 5). Spec membuat kondisi
  // menipis sendiri lewat stok minimum, lalu memulihkannya agar spec lain
  // tidak terpengaruh urutan jalan.
  const previousMin = await setProductMinStock(page, "Semen 40kg", "100000");

  try {
    await page.getByRole("link", { name: "Stok", exact: true }).click();
    await expect(page).toHaveURL("/stok");

    const row = page.getByRole("row", { name: /Semen 40kg/ });
    await expect(row).toBeVisible();
    await expect(row).toContainText("Menipis");

    const aman = page.getByRole("row", { name: /Oli Mesin 1L/ });
    await expect(aman).toContainText("Aman");
  } finally {
    await setProductMinStock(page, "Semen 40kg", previousMin);
  }
});
