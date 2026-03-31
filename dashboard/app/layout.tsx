import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { DOMAIN } from '@/lib/domain'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: `${DOMAIN.companyName} — Operations Hub`,
  description: `Internal operations dashboard for ${DOMAIN.companyName}`,
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className={inter.className}>{children}</body>
    </html>
  )
}
