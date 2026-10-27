// Tampilan waktu untuk user: Asia/Jakarta, Bahasa Indonesia.
// Contoh: "26 Okt 2026, 14.30".

const JAKARTA_TIME = new Intl.DateTimeFormat("id-ID", {
  day: "2-digit",
  month: "short",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  timeZone: "Asia/Jakarta",
});

/** Format ISO/Date ke "26 Okt 2026, 14.30" (WIB). */
export function formatTanggalWaktu(value: string | Date): string {
  const date = typeof value === "string" ? new Date(value) : value;
  if (Number.isNaN(date.getTime())) return "—";
  return JAKARTA_TIME.format(date);
}
