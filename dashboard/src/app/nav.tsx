'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const NAV_ITEMS = [
  { href: '/', label: 'Dashboard' },
  { href: '/chat', label: 'Chat' },
];

export function NavBar() {
  const pathname = usePathname();

  return (
    <nav style={{
      display: 'flex',
      alignItems: 'center',
      gap: 2,
      padding: '0 24px',
      height: 40,
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
          width: 24, height: 24, borderRadius: 6,
          background: 'linear-gradient(135deg, var(--accent-blue), var(--accent-purple))',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontWeight: 700, fontSize: 11, color: 'white',
        }}>G</div>
        <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-primary)', letterSpacing: '-0.01em' }}>
          GTM Company
        </span>
      </div>

      {NAV_ITEMS.map(item => {
        const isActive = pathname === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
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
    </nav>
  );
}
