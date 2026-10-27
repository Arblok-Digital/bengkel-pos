import { expect, test } from "@playwright/test";

import { ensureShift, login } from "./helpers";

test("transaksi offline masuk outbox lalu tersinkron saat online", async ({
  page,
  context,
}) => {
  test.slow();
  test.setTimeout(120_000);

  await login(page);
  await ensureShift(page);

  const status = page.locator("div[role='status']");
  const queued = /menunggu sinkron/;

  await expect(status).toContainText(/Terakhir sinkron \d/);

  const search = page.getByPlaceholder(/Cari nama/);
  const payButton = page.getByRole("button", { name: "Bayar & simpan" });

  // Online: transaksi langsung tersimpan ke server.
  await search.fill("Oli");
  await page.getByRole("button", { name: /Oli Mesin 1L/ }).click();
  await page.getByRole("button", { name: "100.000", exact: true }).click();
  await expect(payButton).toBeEnabled({ timeout: 30_000 });
  await payButton.click();
  await expect(page.getByText(/Transaksi tersimpan: INV-/)).toBeVisible();

  // Offline: transaksi masuk antrean lokal dengan nomor sementara.
  await context.setOffline(true);
  try {
    await expect(status).toContainText("Offline");

    await search.fill("Semen");
    await page.getByRole("button", { name: /Semen 40kg/ }).click();
    await page.getByRole("button", { name: "100.000", exact: true }).click();
    await expect(payButton).toBeEnabled({ timeout: 30_000 });
    await payButton.click();

    await expect(
      page.getByText(/Transaksi tersimpan di perangkat: TMP-/)
    ).toBeVisible();

    // Antrean lokal wajib terisi sebelum bisa disinkron.
    await expect(status).toContainText(queued);

    const pendingInDb = await page.evaluate(async () => {
      const databases = await indexedDB.databases();
      if (!databases.some((db) => db.name === "bengkel-pos")) return -1;

      return new Promise<number>((resolve, reject) => {
        const request = indexedDB.open("bengkel-pos");
        request.onerror = () => reject(request.error);
        request.onsuccess = () => {
          const db = request.result;
          const tx = db.transaction("outbox", "readonly");
          const count = tx.objectStore("outbox").count();
          count.onsuccess = () => resolve(count.result);
          count.onerror = () => reject(count.error);
        };
      });
    });
    expect(pendingInDb).toBe(1);
  } finally {
    await context.setOffline(false);
  }

  // Offline → online: antrean terkirim otomatis, badge antrean hilang.
  await expect(status).not.toContainText(queued);
  await expect(status).not.toContainText("Offline");
});
