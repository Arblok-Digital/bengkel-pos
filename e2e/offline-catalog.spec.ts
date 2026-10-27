import { expect, test } from "@playwright/test";

import { ensureShift, login } from "./helpers";

test("katalog tersimpan di Dexie dan pencarian kasir jalan saat offline", async ({
  page,
  context,
}) => {
  test.slow();

  await login(page);
  await ensureShift(page);
  await expect(page.getByRole("heading", { name: "Kasir" })).toBeVisible();

  const status = page.getByRole("status");
  const syncButton = page.getByRole("button", { name: /sinkron/i });

  await expect(status).toContainText(/Terakhir sinkron \d/);
  // Tunggu revalidasi latar selesai supaya tombol tidak sedang berputar.
  await expect(syncButton).toBeEnabled();

  // Cache Dexie benar-benar berisi produk (bukan hanya state React).
  await expect
    .poll(
      async () =>
        page.evaluate(async () => {
          const databases = await indexedDB.databases();
          if (!databases.some((db) => db.name === "bengkel-pos")) return 0;

          return new Promise<number>((resolve, reject) => {
            const request = indexedDB.open("bengkel-pos");
            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
              const db = request.result;
              const tx = db.transaction("products", "readonly");
              const count = tx.objectStore("products").count();
              count.onsuccess = () => resolve(count.result);
              count.onerror = () => reject(count.error);
            };
          });
        }),
      { timeout: 20_000 }
    )
    .toBeGreaterThan(0);

  await context.setOffline(true);
  try {
    await expect(status).toContainText("Offline");
    await expect(status).toContainText("pencarian dari cache lokal");

    const search = page.getByPlaceholder(/Cari nama/);

    await search.fill("Oli");
    await expect(
      page.getByRole("button", { name: /Oli Mesin 1L/ })
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: /Semen 40kg/ })
    ).toHaveCount(0);

    await search.fill("OLI-1L");
    await expect(
      page.getByRole("button", { name: /Oli Mesin 1L/ })
    ).toBeVisible();

    await search.fill("8999001");
    await expect(
      page.getByRole("button", { name: /Oli Mesin 1L/ })
    ).toBeVisible();

    await expect(syncButton).toBeDisabled();
  } finally {
    await context.setOffline(false);
  }

  await expect(status).not.toContainText("Offline");
  await expect(status).toContainText(/Online/);
  await expect(syncButton).toBeEnabled();

  await syncButton.click();
  await expect(syncButton).toHaveText(/Sinkron ulang/);
  await expect(status).toContainText(/Terakhir sinkron \d/);
});
