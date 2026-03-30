import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'GTM Company — AI Integrators Dashboard',
  description: 'Real-time autonomous agent monitoring and pipeline intelligence',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
