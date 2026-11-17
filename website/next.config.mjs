// Served behind nginx at /frontend. Exposed to client code as
// NEXT_PUBLIC_BASE_PATH because Next adds the basePath to <Link> and
// router.push, but NOT to fetch(): client calls to "/api/..." only worked
// through an nginx rewrite and 404'd when the app was reached directly.
const basePath = '/frontend'

/** @type {import('next').NextConfig} */
const nextConfig = {
  basePath,
  env: {
    NEXT_PUBLIC_BASE_PATH: basePath,
  },
  reactStrictMode: true,
  poweredByHeader: false,
  compress: true,
  productionBrowserSourceMaps: false,
  output: 'standalone',
  images: {
    formats: ['image/avif', 'image/webp'],
    unoptimized: true,
    minimumCacheTTL: 60,
  },
  headers: async () => [
    // Security headers (X-Frame-Options, X-Content-Type-Options, CSP,
    // Referrer-Policy, Permissions-Policy, HSTS) are set by nginx, which
    // fronts every request. Emitting them here as well sent duplicates, and
    // X-Frame-Options even conflicted (DENY here vs SAMEORIGIN in nginx).
    {
      source: '/api/:path*',
      headers: [
        {
          key: 'Cache-Control',
          value: 'no-store, max-age=0',
        },
      ],
    },
    {
      source: '/_next/static/:path*',
      headers: [
        {
          key: 'Cache-Control',
          value: 'public, max-age=31536000, immutable',
        },
      ],
    },
  ],
  // ignoreDuringBuilds / ignoreBuildErrors were both true, which hid 13
  // TypeScript errors - three of them genuine type-safety failures in the todo
  // store. See AUDIT QA-002.
}

export default nextConfig
