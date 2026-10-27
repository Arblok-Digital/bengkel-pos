// Membuat ikon PWA (PNG) tanpa dependensi: rasterisasi bentuk sederhana lalu
// encode PNG pakai zlib bawaan Node. Jalankan: node scripts/generate-icons.mjs
//
// Ikon: struk kasir putih di atas latar gelap, dengan garis teal + aksen amber.
// Versi "maskable" memakai latar penuh dan konten di dalam safe zone 80%.

import { deflateSync } from "node:zlib";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const OUT_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "public",
  "icons"
);

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) {
    c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, "ascii");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([length, typeBuf, data, crc]);
}

function encodePng(size, rgba) {
  const stride = size * 4 + 1;
  const raw = Buffer.alloc(stride * size);
  for (let y = 0; y < size; y += 1) {
    raw[y * stride] = 0; // filter: none
    rgba.copy(raw, y * stride + 1, y * size * 4, (y + 1) * size * 4);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type: RGBA
  ihdr[10] = 0; // deflate
  ihdr[11] = 0; // adaptive filtering
  ihdr[12] = 0; // no interlace

  return Buffer.concat([
    SIG,
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const BG = [15, 23, 42];
const PAPER = [255, 255, 255];
const INK = [13, 148, 136];
const ACCENT = [245, 158, 11];

const SUPERSAMPLE = 4;

function insideRoundedRect(nx, ny, x0, y0, x1, y1, r) {
  if (nx < x0 || nx > x1 || ny < y0 || ny > y1) return false;
  const cx = Math.min(Math.max(nx, x0 + r), x1 - r);
  const cy = Math.min(Math.max(ny, y0 + r), y1 - r);
  const dx = nx - cx;
  const dy = ny - cy;
  return dx * dx + dy * dy <= r * r;
}

function render(size, { rounded, scale }) {
  const s = size * SUPERSAMPLE;
  const buf = Buffer.alloc(s * s * 4); // RGBA, awalnya transparan

  const place = (n) => 0.5 + (n - 0.5) * scale;

  for (let py = 0; py < s; py += 1) {
    const ny = (py + 0.5) / s;
    for (let px = 0; px < s; px += 1) {
      const nx = (px + 0.5) / s;
      const i = (py * s + px) * 4;

      const bgVisible = rounded
        ? insideRoundedRect(nx, ny, 0, 0, 1, 1, 0.22)
        : true;
      if (!bgVisible) continue;

      let color = BG;

      const sx = place(nx);
      const sy = place(ny);

      if (insideRoundedRect(sx, sy, 0.24, 0.16, 0.76, 0.84, 0.07)) {
        color = PAPER;

        const bar = (y0, x1) =>
          insideRoundedRect(sx, sy, 0.32, y0, x1, y0 + 0.055, 0.027);

        if (bar(0.29, 0.68)) color = INK;
        else if (bar(0.42, 0.68)) color = INK;
        else if (bar(0.55, 0.68)) color = INK;
        else if (bar(0.68, 0.5)) color = ACCENT;
      }

      buf[i] = color[0];
      buf[i + 1] = color[1];
      buf[i + 2] = color[2];
      buf[i + 3] = 255;
    }
  }

  // Downsample supersample -> ukuran final (rata-rata, jadi tepi halus).
  const out = Buffer.alloc(size * size * 4);
  const block = SUPERSAMPLE * SUPERSAMPLE;
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      for (let dy = 0; dy < SUPERSAMPLE; dy += 1) {
        for (let dx = 0; dx < SUPERSAMPLE; dx += 1) {
          const i =
            ((y * SUPERSAMPLE + dy) * s + (x * SUPERSAMPLE + dx)) * 4;
          r += buf[i];
          g += buf[i + 1];
          b += buf[i + 2];
          a += buf[i + 3];
        }
      }
      const o = (y * size + x) * 4;
      out[o] = Math.round(r / block);
      out[o + 1] = Math.round(g / block);
      out[o + 2] = Math.round(b / block);
      out[o + 3] = Math.round(a / block);
    }
  }

  return encodePng(size, out);
}

const targets = [
  ["icon-192.png", 192, { rounded: true, scale: 1 }],
  ["icon-512.png", 512, { rounded: true, scale: 1 }],
  ["icon-maskable-192.png", 192, { rounded: false, scale: 0.8 }],
  ["icon-maskable-512.png", 512, { rounded: false, scale: 0.8 }],
  ["apple-touch-icon.png", 180, { rounded: false, scale: 0.88 }],
];

mkdirSync(OUT_DIR, { recursive: true });
for (const [name, size, options] of targets) {
  const png = render(size, options);
  writeFileSync(join(OUT_DIR, name), png);
  console.log(`${name} (${size}px, ${png.length} bita)`);
}
console.log(`Ikon ditulis ke public/icons/`);
