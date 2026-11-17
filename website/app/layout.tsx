import type { Metadata } from "next"
import "./globals.css"
import { Toaster } from "@/components/ui/sonner"


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
      <body className={`font-sans antialiased`}>
        {children}
        {/* toast() is called across the app but nothing rendered it. */}
        <Toaster richColors position="top-right" />
      </body>
    </html>
  )
}
