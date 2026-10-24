import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
  typedRoutes: true,
  poweredByHeader: false,
  reactCompiler: true,
  agentRules: false,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
  experimental: {
    // babel-plugin-react-compiler を入れずに React Compiler を動かすため
    // https://nextjs.org/docs/app/api-reference/config/next-config-js/turbopackRustReactCompiler
    turbopackRustReactCompiler: true,
  },
};

export default nextConfig;
