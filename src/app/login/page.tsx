import { LoginForm } from "./login-form";

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center p-8">
      <div className="flex w-full max-w-sm flex-col items-center gap-6">
        <div className="text-center">
          <h1 className="text-2xl font-bold">Kasir Bengkel &amp; Toko Bangunan</h1>
          <p className="text-muted-foreground mt-1 text-sm">Masuk ke akun Anda</p>
        </div>
        <LoginForm />
      </div>
    </main>
  );
}
