import { describe, expect, it } from "vitest";

import { formatTanggalWaktu } from "./datetime";

describe("formatTanggalWaktu", () => {
  it("memakai format Indonesia dan zona Asia/Jakarta", () => {
    const formatted = formatTanggalWaktu("2026-10-26T07:30:00.000Z");
    expect(formatted).toContain("26 Okt 2026");
    expect(formatted).toContain("14.30");
  });

  it("mengembalikan tanda hubung untuk tanggal tidak valid", () => {
    expect(formatTanggalWaktu("bukan-tanggal")).toBe("—");
  });
});
