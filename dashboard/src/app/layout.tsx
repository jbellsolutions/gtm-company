import type { Metadata } from 'next';
import './globals.css';
import { NavBar } from './nav';
import { AuthProvider } from '../lib/auth';

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
      <body>
        <AuthProvider>
          <NavBar />
          {children}
        </AuthProvider>
      </body>
    </html>
  );
}
