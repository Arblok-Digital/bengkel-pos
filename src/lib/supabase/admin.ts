import { createClient } from "@supabase/supabase-js";

import type { Database } from "./types";

/**
 * Client dengan service role. HANYA boleh dipakai di server (server action /
 * server component). Jangan pernah diimpor dari komponen client.
 */
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY belum diset");
  }

  return createClient<Database>(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
