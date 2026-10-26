"use client";

import { useState } from "react";

import { Button } from "@/components/ui/button";
import {
  importProductsCsvAction,
  previewProductsCsvAction,
  type ImportPreview,
} from "@/features/catalog/import-actions";
import { formatRupiah } from "@/lib/money";

export function ImportCsvForm({ tenantId }: { tenantId: string }) {
  const [csv, setCsv] = useState("");
  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [imported, setImported] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);

  function resetResult() {
    setPreview(null);
    setError(null);
    setImported(null);
  }

  async function onFile(file: File | undefined) {
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) {
      setError("Ukuran file maksimal 2 MB.");
      return;
    }
    resetResult();
    setCsv(await file.text());
  }

  async function onPreview() {
    setLoading(true);
    resetResult();
    try {
      const result = await previewProductsCsvAction(tenantId, csv);
      if (result.error) {
        setError(result.error);
      } else if (result.preview) {
        setPreview(result.preview);
      }
    } catch {
      setError("Gagal membaca CSV.");
    } finally {
      setLoading(false);
    }
  }

  async function onImport() {
    setLoading(true);
    setError(null);
    try {
      const result = await importProductsCsvAction(tenantId, csv);
      if (result.error) {
        setError(result.error);
      } else {
        setImported(result.imported);
        setPreview(null);
      }
    } catch {
      setError("Gagal mengimpor produk.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="rounded-lg border bg-card p-4">
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Pilih file CSV</span>
          <input
            type="file"
            accept=".csv,text/csv"
            onChange={(event) => onFile(event.target.files?.[0])}
            className="text-sm"
          />
        </label>

        <label className="mt-3 flex flex-col gap-1 text-sm">
          <span className="font-medium">Atau tempel isi CSV</span>
          <textarea
            value={csv}
            onChange={(event) => {
              setCsv(event.target.value);
              resetResult();
            }}
            rows={8}
            placeholder="nama,sku,barcode,kategori,satuan,harga_jual,stok_minimum,jenis"
            className="rounded-md border border-input bg-background p-2 font-mono text-xs"
          />
        </label>

        <div className="mt-3 flex flex-wrap items-center gap-3">
          <Button
            type="button"
            onClick={onPreview}
            disabled={loading || csv.trim() === ""}
            className="h-9"
          >
            {loading ? "Memproses..." : "Pratinjau"}
          </Button>
          {preview && preview.errorCount === 0 && preview.validCount > 0 ? (
            <Button
              type="button"
              onClick={onImport}
              disabled={loading}
              className="h-9"
            >
              {loading
                ? "Mengimpor..."
                : `Impor ${preview.validCount} produk`}
            </Button>
          ) : null}
        </div>

        {error ? (
          <p className="mt-3 text-sm text-destructive" role="alert">
            {error}
          </p>
        ) : null}
        {imported !== null ? (
          <p className="mt-3 text-sm text-green-700" role="status">
            {imported} produk berhasil diimpor. Buka menu Produk untuk melihat.
          </p>
        ) : null}
      </div>

      {preview ? (
        <div className="flex flex-col gap-3">
          <div className="rounded-lg border bg-card p-4 text-sm">
            <p>
              {preview.total} baris &middot; {preview.validCount} valid &middot;{" "}
              <span
                className={
                  preview.errorCount > 0 ? "font-semibold text-destructive" : ""
                }
              >
                {preview.errorCount} error
              </span>
            </p>

            {preview.errorCount > 0 ? (
              <ul className="mt-2 list-inside list-disc text-destructive">
                {preview.errors.slice(0, 100).map((item) => (
                  <li key={`${item.line}-${item.message}`}>
                    Baris {item.line}: {item.message}
                  </li>
                ))}
              </ul>
            ) : null}
            {preview.errors.length > 100 ? (
              <p className="text-muted-foreground mt-1">
                ... dan {preview.errors.length - 100} error lain.
              </p>
            ) : null}
          </div>

          {preview.validCount > 0 ? (
            <div className="overflow-x-auto rounded-lg border bg-card">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-muted-foreground">
                    <th className="p-2 font-medium">Baris</th>
                    <th className="p-2 font-medium">Nama</th>
                    <th className="p-2 font-medium">SKU</th>
                    <th className="p-2 font-medium">Satuan</th>
                    <th className="p-2 font-medium">Harga</th>
                    <th className="p-2 font-medium">Jenis</th>
                  </tr>
                </thead>
                <tbody>
                  {preview.rows.slice(0, 20).map((row) => (
                    <tr key={row.line} className="border-b last:border-0">
                      <td className="p-2">{row.line}</td>
                      <td className="p-2">{row.name}</td>
                      <td className="p-2">{row.sku || "—"}</td>
                      <td className="p-2">{row.unitName}</td>
                      <td className="p-2">{formatRupiah(row.sellPrice)}</td>
                      <td className="p-2">{row.kind}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {preview.rows.length > 20 ? (
                <p className="text-muted-foreground p-2 text-xs">
                  Menampilkan 20 dari {preview.rows.length} baris valid.
                </p>
              ) : null}
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
