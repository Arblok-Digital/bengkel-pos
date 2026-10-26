import { describe, expect, it } from "vitest";
import { cn } from "@/lib/utils";

describe("cn", () => {
  it("menggabungkan class name", () => {
    expect(cn("h-12", "min-h-12")).toBe("h-12 min-h-12");
  });

  it("menghapus class yang saling konflik (tailwind-merge)", () => {
    expect(cn("px-4", "px-2")).toBe("px-2");
  });
});
