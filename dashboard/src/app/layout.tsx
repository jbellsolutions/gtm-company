import type { Metadata } from 'next';
import './globals.css';
import { NavBar } from './nav';
import { AuthProvider } from '../lib/auth';

export const metadata: Metadata = {
  title: 'AI Integrators — GTM Command Center',
  description: 'Cold Email, Call Center, LinkedIn, Content, Partnerships — all in one place',
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
