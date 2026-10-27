import { withSerwist } from "@serwist/turbopack";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Workspace root: folder ini, supaya Next.js tidak salah menebak
  // karena adanya package-lock.json di folder lain (mis. home directory).
  outputFileTracingRoot: __dirname,
};

export default withSerwist(nextConfig);
