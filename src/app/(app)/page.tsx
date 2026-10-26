import { LogoutButton } from "./logout-button";

export default function DashboardPage() {
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">Beranda</h1>
      <p className="text-muted-foreground">
        Anda sudah masuk. Modul akan muncul di sini seiring fase berikutnya.
      </p>
      <div>
        <LogoutButton />
      </div>
    </div>
  );
}
