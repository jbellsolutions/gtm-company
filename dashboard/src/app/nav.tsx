'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAuth } from '../lib/auth';

const NAV_ITEMS = [
  { href: '/', label: 'Overview' },
  { href: '/emails', label: 'Cold Email' },
  { href: '/calls', label: 'Call Center' },
  { href: '/chat', label: 'Chat' },
];

export function NavBar() {
  const pathname = usePathname();
  const { user, signOut } = useAuth();

  // Don't show nav on login page
  if (pathname === '/login') return null;

  return (
    <nav style={{
      display: 'flex',
      alignItems: 'center',
      gap: 2,
      padding: '0 24px',
      height: 48,
      background: 'var(--bg-primary)',
      borderBottom: '1px solid var(--border)',
      position: 'sticky',
      top: 0,
      zIndex: 200,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12,
        marginRight: 24,
      }}>
        <div style={{
          width: 28, height: 28, borderRadius: 6,
          background: 'linear-gradient(135deg, var(--accent-blue), var(--accent-purple))',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontWeight: 700, fontSize: 12, color: 'white',
        }}>AI</div>
        <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1.2 }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-primary)', letterSpacing: '-0.01em' }}>
            AI Integrators
          </span>
          <span style={{ fontSize: 10, color: 'var(--text-muted)', letterSpacing: '0.04em', textTransform: 'uppercase' }}>
            GTM Command Center
          </span>
        </div>
      </div>

      {NAV_ITEMS.map(item => {
        const isActive = pathname === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
            className={`nav-tab ${isActive ? 'nav-tab-active' : ''}`}
            style={{
              padding: '8px 14px',
              fontSize: 12,
              fontWeight: 500,
              color: isActive ? 'var(--text-primary)' : 'var(--text-secondary)',
              textDecoration: 'none',
              borderRadius: 6,
              background: isActive ? 'var(--bg-card-hover)' : 'transparent',
              transition: 'all 0.15s ease',
              position: 'relative',
            }}
          >
            {item.label}
            {isActive && (
              <div style={{
                position: 'absolute',
                bottom: -1,
                left: '50%',
                transform: 'translateX(-50%)',
                width: 20,
                height: 2,
                borderRadius: 1,
                background: 'var(--accent-blue)',
              }} />
            )}
          </Link>
        );
      })}

      {/* Spacer + Sign Out */}
      <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 12 }}>
        {user && (
          <>
            <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
              {user.email}
            </span>
            <button
              onClick={signOut}
              style={{
                background: 'transparent',
                border: '1px solid var(--border)',
                borderRadius: 6,
                padding: '4px 10px',
                fontSize: 11,
                color: 'var(--text-secondary)',
                cursor: 'pointer',
                transition: 'all 0.15s ease',
              }}
            >
              Sign Out
            </button>
          </>
        )}
      </div>
    </nav>
  );
}
