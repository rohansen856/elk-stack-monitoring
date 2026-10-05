/** @type {import('next').NextConfig} */
const nextConfig = {
  basePath: '/frontend',
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
    {
      source: '/:path*',
      headers: [
        {
          key: 'X-Content-Type-Options',
          value: 'nosniff',
        },
        {
          key: 'X-Frame-Options',
          value: 'DENY',
        },
        {
          key: 'X-XSS-Protection',
          value: '1; mode=block',
        },
        {
          key: 'Referrer-Policy',
          value: 'strict-origin-when-cross-origin',
        },
        {
          key: 'Permissions-Policy',
          value: 'geolocation=(), microphone=(), camera=()',
        },
          // Strict-Transport-Security is set by nginx, which terminates TLS.
          // Emitting it here as well produced a duplicate header.
      ],
    },
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
