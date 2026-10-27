"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";
import type { ReceivableDetailData, ReceivablePaymentItem } from "@/features/ar/queries";
import { formatRupiah } from "@/lib/money";

export function KwitansiView({
  data,
  payment,
}: {
  data: ReceivableDetailData;
  payment: ReceivablePaymentItem;
}) {
  const { receivable, sale, customer, settings } = data;

  const paidDate = new Intl.DateTimeFormat("id-ID", {
    dateStyle: "long",
    timeStyle: "short",
  }).format(new Date(payment.paidAt));

  // Compute accumulated paid up to this payment
  let totalPaidUpToThis = 0;
  for (const p of data.payments) {
    totalPaidUpToThis += p.amount;
    if (p.id === payment.id) break;
  }
  const remainingAfterThis = Math.max(0, receivable.amount - totalPaidUpToThis);
  const kwitansiNo = `KW-${sale.invoiceNo}-${payment.id.slice(0, 6).toUpperCase()}`;

  const shareText = [
    `*${settings.storeName}*`,
    `*KWITANSI PEMBAYARAN PIUTANG*`,
    `No: ${kwitansiNo}`,
    `Tanggal: ${paidDate}`,
    `Pelanggan: ${customer.name}`,
    `Faktur Asli: ${sale.invoiceNo}`,
    `--------------------------------`,
    `Nominal Cicilan: ${formatRupiah(payment.amount)}`,
    `Metode: ${payment.method.toUpperCase()}${payment.reference ? ` (${payment.reference})` : ""}`,
    `Sisa Piutang: ${formatRupiah(remainingAfterThis)}`,
    `Status: ${remainingAfterThis === 0 ? "LUNAS" : "BELUM LUNAS"}`,
    `--------------------------------`,
    `Terima kasih. Simpan kwitansi ini sebagai bukti pembayaran sah.`,
  ].join("\n");

  const phoneDigits = (customer.phone ?? "").replace(/\D/g, "");
  const waPhone = phoneDigits.startsWith("0") ? `62${phoneDigits.slice(1)}` : phoneDigits;
  const waHref = waPhone
    ? `https://wa.me/${waPhone}?text=${encodeURIComponent(shareText)}`
    : null;

  return (
    <div className="mx-auto max-w-2xl">
      {/* Action Buttons (Hidden on Print) */}
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Link
          href={`/piutang/${receivable.id}`}
          className="text-sm font-medium text-muted-foreground hover:text-foreground"
        >
          &larr; Kembali ke Detail Piutang
        </Link>
        <div className="flex items-center gap-2">
          {waHref ? (
            <a
              href={waHref}
              target="_blank"
              rel="noreferrer"
              className="inline-flex h-9 items-center rounded-md border border-emerald-600 px-3 text-xs font-semibold text-emerald-700 hover:bg-emerald-50"
            >
              Kirim ke WA Pelanggan
            </a>
          ) : null}
          <Button
            onClick={() => window.print()}
            className="h-9 px-4 text-xs font-semibold"
            data-testid="btn-print-kwitansi"
          >
            Cetak Kwitansi
          </Button>
        </div>
      </div>

      {/* Kwitansi Printable Card */}
      <div className="rounded-xl border border-stone-300 bg-white p-8 text-stone-900 shadow-sm print:border-none print:p-0 print:shadow-none">
        {/* Store Header */}
        <div className="border-b pb-4 text-center">
          <h2 className="text-xl font-bold tracking-tight">{settings.storeName}</h2>
          {settings.address ? (
            <p className="mt-0.5 text-xs text-stone-600">{settings.address}</p>
          ) : null}
          {settings.phone ? (
            <p className="text-xs text-stone-600">Telp: {settings.phone}</p>
          ) : null}
        </div>

        {/* Kwitansi Title & Number */}
        <div className="mt-4 flex items-center justify-between border-b pb-3 text-xs">
          <div>
            <span className="font-mono text-stone-500">NO: </span>
            <span className="font-mono font-bold text-stone-800">{kwitansiNo}</span>
          </div>
          <div className="text-right">
            <span className="text-stone-500">Tanggal: </span>
            <span className="font-medium">{paidDate}</span>
          </div>
        </div>

        <div className="my-4 text-center">
          <h1 className="text-lg font-black uppercase tracking-wider text-stone-800">
            Kwitansi Pembayaran
          </h1>
        </div>

        {/* Body Details */}
        <div className="space-y-3 text-sm">
          <div className="flex border-b border-stone-100 py-1.5">
            <span className="w-44 text-stone-500">Telah Diterima Dari</span>
            <span className="font-bold text-stone-900">: {customer.name}</span>
          </div>

          <div className="flex border-b border-stone-100 py-1.5">
            <span className="w-44 text-stone-500">Untuk Pembayaran</span>
            <span className="text-stone-900">
              : Cicilan Piutang Faktur <strong>#{sale.invoiceNo}</strong>
            </span>
          </div>

          <div className="flex border-b border-stone-100 py-1.5">
            <span className="w-44 text-stone-500">Metode Bayar</span>
            <span className="uppercase text-stone-900">
              : {payment.method} {payment.reference ? `(Ref: ${payment.reference})` : ""}
            </span>
          </div>

          {/* Amount Box */}
          <div className="my-4 rounded-lg border-2 border-dashed border-stone-300 bg-stone-50 p-4">
            <span className="text-xs font-semibold uppercase text-stone-500">
              Jumlah Uang Dibayar:
            </span>
            <div className="mt-1 text-2xl font-black text-stone-900" data-testid="kwitansi-amount">
              {formatRupiah(payment.amount)}
            </div>
          </div>

          {/* Balance breakdown */}
          <div className="rounded-lg bg-stone-50 p-3 text-xs space-y-1">
            <div className="flex justify-between">
              <span className="text-stone-600">Total Tagihan Awal:</span>
              <span className="font-medium">{formatRupiah(receivable.amount)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-stone-600">Total Dibayar s.d. Saat Ini:</span>
              <span className="font-medium text-emerald-700">{formatRupiah(totalPaidUpToThis)}</span>
            </div>
            <div className="flex justify-between border-t border-stone-200 pt-1 font-bold">
              <span className="text-stone-700">Sisa Saldo Piutang:</span>
              <span className={remainingAfterThis === 0 ? "text-emerald-700" : "text-amber-700"}>
                {formatRupiah(remainingAfterThis)}{" "}
                {remainingAfterThis === 0 ? "(LUNAS)" : ""}
              </span>
            </div>
          </div>
        </div>

        {/* Signatures */}
        <div className="mt-8 grid grid-cols-2 text-center text-xs">
          <div>
            <p className="text-stone-500">Penyetor,</p>
            <div className="h-16"></div>
            <p className="font-semibold underline">{customer.name}</p>
          </div>
          <div>
            <p className="text-stone-500">Penerima (Kasir),</p>
            <div className="h-16"></div>
            <p className="font-semibold underline">{settings.storeName}</p>
          </div>
        </div>
      </div>
    </div>
  );
}
