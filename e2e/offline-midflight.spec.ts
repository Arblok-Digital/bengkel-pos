import { expect, test } from "@playwright/test";

import { ensureShift, login } from "./helpers";

test("network putus di tengah transaksi dialihkan ke outbox lokal dan disinkronkan saat pulih", async ({
  page,
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

  // Pilih produk dan isi pembayaran tunai saat online
  await search.fill("Oli");
  await page.getByRole("button", { name: /Oli Mesin 1L/ }).click();
  await page.getByRole("button", { name: "100.000", exact: true }).click();
  await expect(payButton).toBeEnabled({ timeout: 30_000 });

  // Simulasikan koneksi putus di tengah jalan saat tombol bayar ditekan (mid-flight network failure)
  let intercepted = false;
  await page.route("**/kasir*", async (route) => {
    if (route.request().method() === "POST") {
      intercepted = true;
      await route.abort("failed");
    } else {
      await route.continue();
    }
  });

  await payButton.click();

  // Transaksi dialihkan ke antrean perangkat dengan nomor sementara TMP-
  await expect(
    page.getByText(/Transaksi tersimpan di perangkat: TMP-/)
  ).toBeVisible({ timeout: 15_000 });
  expect(intercepted).toBe(true);

  // Status kasir menampilkan antrean menunggu sinkron
  await expect(status).toContainText(queued);

  // Verifikasi isi antrean lokal di IndexedDB
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

  // Pulihkan koneksi jaringan (cabut interceptor abort)
  await page.unrouteAll();

  // Kirim antrean sekarang
  const sendNowButton = page.getByRole("button", { name: /Kirim sekarang|Kirim antrean/i }).first();
  await expect(sendNowButton).toBeEnabled();
  await sendNowButton.click();

  // Badge antrean hilang setelah berhasil disinkronkan ke server
  await expect(status).not.toContainText(queued, { timeout: 15_000 });
});
