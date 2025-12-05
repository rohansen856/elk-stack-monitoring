import type { Metadata } from "next"
import { Geist, Geist_Mono } from "next/font/google"
import "./globals.css"

const _geist = Geist({ subsets: ["latin"] })
const _geistMono = Geist_Mono({ subsets: ["latin"] })

export const metadata: Metadata = {
  title: "Sentinel Todo",
  description: "A modern, productive task management application",
  icons: {
    icon: [
      {
        url: "/frontend/ms-icon-70x70.png",
        media: "(prefers-color-scheme: light)",
      },
      {
        url: "/frontend/ms-icon-70x70.png",
        media: "(prefers-color-scheme: dark)",
      },
      {
        url: "/frontend/icon.svg",
        type: "image/svg+xml",
      },
    ],
    apple: "/frontend/apple-icon.png",
  },
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en">
      <body className={`font-sans antialiased`}>{children}</body>
    </html>
  )
}
