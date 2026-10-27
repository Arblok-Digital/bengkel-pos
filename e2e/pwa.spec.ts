import { expect, test } from "@playwright/test";

test("manifest PWA valid: nama, ikon 192/512, standalone", async ({
  page,
}) => {
  await page.goto("/login");

  const href = await page
    .locator('link[rel="manifest"]')
    .getAttribute("href");
  expect(href).toBeTruthy();

  const response = await page.request.get(href as string);
  expect(response.ok()).toBeTruthy();

  const manifest = (await response.json()) as {
    name: string;
    short_name: string;
    start_url: string;
    display: string;
    theme_color: string;
    icons: { src: string; sizes: string; type: string; purpose?: string }[];
  };

  expect(manifest.name).toContain("Kasir Bengkel");
  expect(manifest.short_name).toBeTruthy();
  expect(manifest.start_url).toBe("/kasir");
  expect(manifest.display).toBe("standalone");
  expect(manifest.theme_color).toBeTruthy();

  const sizes = manifest.icons.map((icon) => icon.sizes);
  expect(sizes).toContain("192x192");
  expect(sizes).toContain("512x512");
  expect(manifest.icons.some((icon) => icon.purpose === "maskable")).toBe(true);

  for (const icon of manifest.icons) {
    const iconResponse = await page.request.get(icon.src);
    expect(iconResponse.ok(), `ikon ${icon.src} harus ada`).toBeTruthy();
    expect(iconResponse.headers()["content-type"]).toContain("image/png");
  }
});

test("service worker aktif dan halaman offline tampil saat jaringan mati", async ({
  page,
  context,
}) => {
  test.slow();
  await page.goto("/login");

  const scope = await page.evaluate(async () => {
    const registration = await navigator.serviceWorker.ready;
    return registration.scope;
  });
  expect(scope).toContain("localhost:3000");

  // Muat ulang sekali supaya service worker mengontrol halaman ini.
  await page.reload();
  await expect
    .poll(() => page.evaluate(() => Boolean(navigator.serviceWorker.controller)), {
      timeout: 15_000,
    })
    .toBe(true);

  await context.setOffline(true);
  try {
    await page.goto("/kasir").catch(() => undefined);
    await expect(
      page.getByRole("heading", { name: /Tidak ada koneksi internet/i })
    ).toBeVisible();
  } finally {
    await context.setOffline(false);
  }
});
