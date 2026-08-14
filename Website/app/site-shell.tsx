/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import type { ReactNode } from "react";

export function SiteShell({ children }: { children: ReactNode }) {
  return (
    <div className="site-shell">
      <header className="site-header">
        <Link className="brand" href="/" aria-label="Cleave home">
          <img className="brand-logo" src="/cleave-logo-enhanced.png" alt="" width="42" height="42" />
          <span>Cleave</span>
        </Link>
        <nav aria-label="Main navigation">
          <Link href="/privacy">Privacy</Link>
          <Link href="/support">Support</Link>
        </nav>
      </header>
      {children}
      <footer className="site-footer">
        <div>
          <Link className="brand footer-brand" href="/">
            <img className="brand-logo footer-logo" src="/cleave-logo-enhanced.png" alt="" width="36" height="36" />
            <span>Cleave</span>
          </Link>
          <p>Sever the debt. Keep the ties.</p>
        </div>
        <div className="footer-links">
          <Link href="/privacy">Privacy</Link>
          <Link href="/support">Support</Link>
          <a href="mailto:cleave.receipts@gmail.com">Contact</a>
        </div>
        <p className="copyright">© 2026 Cleave</p>
      </footer>
    </div>
  );
}
