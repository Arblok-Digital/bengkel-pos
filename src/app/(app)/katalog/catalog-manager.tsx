"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import {
  createCategoryAction,
  createUnitAction,
  deleteCategoryAction,
  deleteUnitAction,
  renameCategoryAction,
  renameUnitAction,
  type CatalogActionState,
} from "@/features/catalog/actions";
import type { CatalogData, CatalogItem } from "@/features/catalog/queries";

const initialState: CatalogActionState = { error: null, success: null };

export function CatalogManager({ data }: { data: CatalogData }) {
  return (
    <div className="flex flex-col gap-6">
      <CategorySection data={data} />
      <UnitSection data={data} />
      {!data.canWrite ? (
        <p className="text-muted-foreground text-sm">
          Hanya pemilik/admin yang dapat mengubah katalog.
        </p>
      ) : null}
    </div>
  );
}

function CategorySection({ data }: { data: CatalogData }) {
  return (
    <section className="rounded-lg border bg-card p-4">
      <h2 className="text-lg font-semibold">Kategori</h2>

      {data.canWrite ? <AddCategoryForm tenantId={data.tenantId} /> : null}

      <div className="mt-3">
        {data.categories.length === 0 ? (
          <p className="text-muted-foreground text-sm">Belum ada kategori.</p>
        ) : (
          data.categories.map((item) => (
            <CategoryRow
              key={item.id}
              tenantId={data.tenantId}
              item={item}
              canWrite={data.canWrite}
            />
          ))
        )}
      </div>
    </section>
  );
}

function UnitSection({ data }: { data: CatalogData }) {
  return (
    <section className="rounded-lg border bg-card p-4">
      <h2 className="text-lg font-semibold">Satuan</h2>

      {data.canWrite ? <AddUnitForm tenantId={data.tenantId} /> : null}

      <div className="mt-3">
        {data.units.length === 0 ? (
          <p className="text-muted-foreground text-sm">Belum ada satuan.</p>
        ) : (
          data.units.map((item) => (
            <UnitRow
              key={item.id}
              tenantId={data.tenantId}
              item={item}
              canWrite={data.canWrite}
            />
          ))
        )}
      </div>
    </section>
  );
}

function AddCategoryForm({ tenantId }: { tenantId: string }) {
  const [state, formAction, pending] = useActionState(
    createCategoryAction,
    initialState
  );

  return (
    <form action={formAction} className="mt-3 flex flex-col gap-2 sm:flex-row">
      <input type="hidden" name="tenantId" value={tenantId} />
      <input
        name="name"
        required
        maxLength={80}
        aria-label="Nama kategori baru"
        placeholder="Nama kategori baru"
        className="h-9 flex-1 rounded-md border border-input bg-background px-2 text-sm"
      />
      <Button type="submit" disabled={pending} className="h-9">
        {pending ? "Menyimpan..." : "Tambah kategori"}
      </Button>
      {state.error ? (
        <p className="text-sm text-destructive" role="alert">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p className="text-sm text-green-700" role="status">
          {state.success}
        </p>
      ) : null}
    </form>
  );
}

function AddUnitForm({ tenantId }: { tenantId: string }) {
  const [state, formAction, pending] = useActionState(
    createUnitAction,
    initialState
  );

  return (
    <form action={formAction} className="mt-3 flex flex-col gap-2 sm:flex-row">
      <input type="hidden" name="tenantId" value={tenantId} />
      <input
        name="name"
        required
        maxLength={30}
        aria-label="Nama satuan baru"
        placeholder="cth: pcs, sak, liter"
        className="h-9 flex-1 rounded-md border border-input bg-background px-2 text-sm"
      />
      <Button type="submit" disabled={pending} className="h-9">
        {pending ? "Menyimpan..." : "Tambah satuan"}
      </Button>
      {state.error ? (
        <p className="text-sm text-destructive" role="alert">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p className="text-sm text-green-700" role="status">
          {state.success}
        </p>
      ) : null}
    </form>
  );
}

function CategoryRow({
  tenantId,
  item,
  canWrite,
}: {
  tenantId: string;
  item: CatalogItem;
  canWrite: boolean;
}) {
  const [renameState, renameAction, renamePending] = useActionState(
    renameCategoryAction,
    initialState
  );
  const [deleteState, deleteAction, deletePending] = useActionState(
    deleteCategoryAction,
    initialState
  );

  if (!canWrite) {
    return <div className="border-b py-2 text-sm last:border-0">{item.name}</div>;
  }

  return (
    <div className="flex flex-col gap-1 border-b py-2 last:border-0">
      <div className="flex items-center gap-2">
        <form action={renameAction} className="flex flex-1 items-center gap-2">
          <input type="hidden" name="tenantId" value={tenantId} />
          <input type="hidden" name="id" value={item.id} />
          <input
            name="name"
            defaultValue={item.name}
            required
            maxLength={80}
            aria-label={`Nama kategori ${item.name}`}
            className="h-8 flex-1 rounded-md border border-input bg-background px-2 text-sm"
          />
          <Button type="submit" size="sm" disabled={renamePending}>
            Simpan
          </Button>
        </form>

        <form action={deleteAction}>
          <input type="hidden" name="tenantId" value={tenantId} />
          <input type="hidden" name="id" value={item.id} />
          <Button
            type="submit"
            variant="destructive"
            size="sm"
            disabled={deletePending}
          >
            Hapus
          </Button>
        </form>
      </div>

      {renameState.error || deleteState.error ? (
        <p className="text-sm text-destructive" role="alert">
          {renameState.error ?? deleteState.error}
        </p>
      ) : null}
      {renameState.success || deleteState.success ? (
        <p className="text-sm text-green-700" role="status">
          {renameState.success ?? deleteState.success}
        </p>
      ) : null}
    </div>
  );
}

function UnitRow({
  tenantId,
  item,
  canWrite,
}: {
  tenantId: string;
  item: CatalogItem;
  canWrite: boolean;
}) {
  const [renameState, renameAction, renamePending] = useActionState(
    renameUnitAction,
    initialState
  );
  const [deleteState, deleteAction, deletePending] = useActionState(
    deleteUnitAction,
    initialState
  );

  if (!canWrite) {
    return <div className="border-b py-2 text-sm last:border-0">{item.name}</div>;
  }

  return (
    <div className="flex flex-col gap-1 border-b py-2 last:border-0">
      <div className="flex items-center gap-2">
        <form action={renameAction} className="flex flex-1 items-center gap-2">
          <input type="hidden" name="tenantId" value={tenantId} />
          <input type="hidden" name="id" value={item.id} />
          <input
            name="name"
            defaultValue={item.name}
            required
            maxLength={30}
            aria-label={`Nama satuan ${item.name}`}
            className="h-8 flex-1 rounded-md border border-input bg-background px-2 text-sm"
          />
          <Button type="submit" size="sm" disabled={renamePending}>
            Simpan
          </Button>
        </form>

        <form action={deleteAction}>
          <input type="hidden" name="tenantId" value={tenantId} />
          <input type="hidden" name="id" value={item.id} />
          <Button
            type="submit"
            variant="destructive"
            size="sm"
            disabled={deletePending}
          >
            Hapus
          </Button>
        </form>
      </div>

      {renameState.error || deleteState.error ? (
        <p className="text-sm text-destructive" role="alert">
          {renameState.error ?? deleteState.error}
        </p>
      ) : null}
      {renameState.success || deleteState.success ? (
        <p className="text-sm text-green-700" role="status">
          {renameState.success ?? deleteState.success}
        </p>
      ) : null}
    </div>
  );
}
