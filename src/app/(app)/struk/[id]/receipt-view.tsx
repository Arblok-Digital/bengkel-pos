"use client";

import Link from "next/link";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import type { PaperWidth, ReceiptData } from "@/features/sales/queries";
import { formatRupiah } from "@/lib/money";

const methodLabel: Record<string, string> = {
  tunai: "Tunai",
  transfer: "Transfer",
  qris: "QRIS",
  debit: "Debit",
  kredit_tempo: "Kredit/tempo",
};

function formatQty(value: number): string {
  return value.toLocaleString("id-ID", { maximumFractionDigits: 3 });
}

export function ReceiptView({ data }: { data: ReceiptData }) {
  const [width, setWidth] = useState<PaperWidth>(data.settings.paperWidth);

  const soldAt = new Intl.DateTimeFormat("id-ID", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(data.soldAt));

  const shareLines = [
    `*${data.settings.storeName}*`,
    `Struk ${data.invoiceNo}`,
    soldAt,
    "",
    ...data.items.map(
      (item) =>
        `${item.name} ${formatQty(item.qty)} ${item.unitName} = ${formatRupiah(
          item.lineTotal
        )}`
    ),
    "",
    `Total: ${formatRupiah(data.total)}`,
    `Dibayar: ${formatRupiah(data.paidAmount)}`,
    data.changeAmount > 0
      ? `Kembalian: ${formatRupiah(data.changeAmount)}`
      : "",
    data.settings.footer ? `\n${data.settings.footer}` : "",
  ].filter((line) => line !== "");

  const phoneDigits = (data.customerPhone ?? "").replace(/\D/g, "");
  const waPhone = phoneDigits.startsWith("0")
    ? `62${phoneDigits.slice(1)}`
    : phoneDigits;
  const waHref = `https://wa.me/${waPhone}?text=${encodeURIComponent(
    shareLines.join("\n")
  )}`;

  const taxPercent =
    data.subtotal > 0 && data.tax > 0
      ? Math.round((data.tax / data.subtotal) * 100)
      : 0;

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2 print:hidden">
        <div>
          <h1 className="text-2xl font-bold">Struk</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            {data.invoiceNo} &middot; {soldAt}
          </p>
        </div>
        <div className="flex flex-wrap gap-2 text-sm">
          <Link
            href="/penjualan"
            className="inline-flex h-11 items-center rounded-md border border-input px-4 hover:bg-accent"
          >
            &larr; Penjualan
          </Link>
          <Link
            href="/kasir"
            className="inline-flex h-11 items-center rounded-md border border-input px-4 hover:bg-accent"
          >
            Kasir
          </Link>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2 print:hidden">
        <Button type="button" className="h-11" onClick={() => window.print()}>
          Cetak struk
        </Button>
        <Button
          type="button"
          variant={width === "58" ? "secondary" : "outline"}
          className="h-11"
          onClick={() => setWidth("58")}
        >
          58 mm
        </Button>
        <Button
          type="button"
          variant={width === "80" ? "secondary" : "outline"}
          className="h-11"
          onClick={() => setWidth("80")}
        >
          80 mm
        </Button>
        <a
          href={waHref}
          target="_blank"
          rel="noreferrer"
          className="inline-flex h-11 items-center rounded-md border border-input px-4 text-sm hover:bg-accent"
        >
          Kirim WhatsApp
        </a>
        <span className="text-muted-foreground text-xs">
          Simpan PDF: pilih &ldquo;Save as PDF&rdquo; di dialog cetak.
        </span>
      </div>

      <div className="flex justify-center print:block">
        <article
          className="receipt-paper rounded-md border bg-white p-4 font-mono text-[11px] leading-snug text-black shadow-sm"
          style={{ width: `${width}mm`, maxWidth: "100%" }}
        >
          {data.settings.logoUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={data.settings.logoUrl}
              alt="Logo toko"
              className="mx-auto mb-2 h-12 object-contain"
            />
          ) : null}

          <div className="text-center">
            <p className="text-sm font-bold uppercase">
              {data.settings.storeName}
            </p>
            {data.settings.address ? <p>{data.settings.address}</p> : null}
            {data.settings.phone ? <p>Telp {data.settings.phone}</p> : null}
          </div>

          <div className="my-2 border-t border-dashed border-black" />

          <div className="flex justify-between gap-2">
            <span>No.</span>
            <span>{data.invoiceNo}</span>
          </div>
          <div className="flex justify-between gap-2">
            <span>Tanggal</span>
            <span>{soldAt}</span>
          </div>
          <div className="flex justify-between gap-2">
            <span>Outlet</span>
            <span>{data.outletName}</span>
          </div>
          {data.customerName ? (
            <div className="flex justify-between gap-2">
              <span>Pelanggan</span>
              <span>{data.customerName}</span>
            </div>
          ) : null}

          <div className="my-2 border-t border-dashed border-black" />

          <ul className="flex flex-col gap-1">
            {data.items.map((item) => (
              <li key={item.id}>
                <div className="flex justify-between gap-2 font-semibold">
                  <span className="break-words">{item.name}</span>
                  <span className="whitespace-nowrap">
                    {formatRupiah(item.lineTotal)}
                  </span>
                </div>
                <div className="flex justify-between gap-2">
                  <span>
                    {formatQty(item.qty)} {item.unitName} x{" "}
                    {formatRupiah(item.unitPrice)}
                  </span>
                  {item.discount > 0 ? (
                    <span>Disk -{formatRupiah(item.discount)}</span>
                  ) : null}
                </div>
                {item.note ? (
                  <p className="text-[10px] italic">{item.note}</p>
                ) : null}
              </li>
            ))}
          </ul>

          <div className="my-2 border-t border-dashed border-black" />

          <div className="flex justify-between gap-2">
            <span>Subtotal</span>
            <span>{formatRupiah(data.subtotal)}</span>
          </div>
          {data.discount > 0 ? (
            <div className="flex justify-between gap-2">
              <span>Diskon</span>
              <span>-{formatRupiah(data.discount)}</span>
            </div>
          ) : null}
          {data.tax > 0 ? (
            <div className="flex justify-between gap-2">
              <span>
                Pajak
                {!data.settings.hideTaxPercent && taxPercent > 0
                  ? ` (${taxPercent}%)`
                  : ""}
              </span>
              <span>{formatRupiah(data.tax)}</span>
            </div>
          ) : null}
          <div className="flex justify-between gap-2 text-sm font-bold">
            <span>TOTAL</span>
            <span>{formatRupiah(data.total)}</span>
          </div>

          <div className="my-2 border-t border-dashed border-black" />

          {data.payments.map((payment) => (
            <div key={payment.id} className="flex justify-between gap-2">
              <span>{methodLabel[payment.method] ?? payment.method}</span>
              <span>{formatRupiah(payment.amount)}</span>
            </div>
          ))}
          <div className="flex justify-between gap-2">
            <span>Dibayar</span>
            <span>{formatRupiah(data.paidAmount)}</span>
          </div>
          {data.changeAmount > 0 ? (
            <div className="flex justify-between gap-2">
              <span>Kembalian</span>
              <span>{formatRupiah(data.changeAmount)}</span>
            </div>
          ) : null}

          {data.status !== "paid" ? (
            <div className="mt-1 flex justify-between gap-2 font-semibold">
              <span>Status</span>
              <span>
                {data.status === "partial"
                  ? "Bayar sebagian / kredit"
                  : data.status === "credit"
                    ? "Kredit / tempo"
                    : data.status}
              </span>
            </div>
          ) : null}

          {data.note ? (
            <p className="mt-2 text-[10px]">Catatan: {data.note}</p>
          ) : null}

          {data.settings.footer ? (
            <>
              <div className="my-2 border-t border-dashed border-black" />
              <p className="whitespace-pre-line text-center">
                {data.settings.footer}
              </p>
            </>
          ) : null}

          <p className="mt-2 text-center">Terima kasih</p>
        </article>
      </div>
    </div>
  );
}
