import { updateSession } from "@/lib/supabase/proxy";
import type { NextRequest } from "next/server";

export async function proxy(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|serwist|manifest.webmanifest|~offline|icons|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
