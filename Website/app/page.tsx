/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import { SiteShell } from "./site-shell";

export default function Home() {
  return (
    <SiteShell>
      <main>
        <section className="hero branded-hero">
          <div className="hero-message">
            <div className="eyebrow">Cleave for iPhone</div>
            <h1>Split the receipt.<br />Keep the memory.</h1>
            <p className="hero-copy">
              Clear answers about collaborative splitting, receipt scanning,
              payments, memories, privacy, and account control.
            </p>
          </div>
          <div className="hero-art" aria-hidden="true">
            <span className="art-orbit orbit-one" />
            <span className="art-orbit orbit-two" />
            <img src="/cleave-logo-enhanced.png" alt="" width="500" height="500" />
          </div>
        </section>

        <section className="link-grid" aria-label="Helpful links">
          <Link className="feature-card privacy-card" href="/privacy">
            <span className="card-number">01</span>
            <div>
              <h2>Privacy policy</h2>
              <p>What Cleave collects, why it is used, and the choices you have.</p>
            </div>
            <span className="card-arrow" aria-hidden="true">↗</span>
          </Link>
          <Link className="feature-card support-card" href="/support">
            <span className="card-number">02</span>
            <div>
              <h2>Support</h2>
              <p>Get help with your account, groups, receipt scans, and data.</p>
            </div>
            <span className="card-arrow" aria-hidden="true">↗</span>
          </Link>
        </section>

        <section className="trust-strip">
          <div><strong>Access checked</strong><span>The backend verifies account, group, receipt, and admin access before returning collaborative data.</span></div>
          <div><strong>Private media</strong><span>Receipt, profile, and memory images are not stored as public links.</span></div>
          <div><strong>No ad tracking</strong><span>Cleave does not sell personal data or use it for targeted advertising.</span></div>
        </section>

        <section className="plain-security" aria-labelledby="security-title">
          <div>
            <span className="eyebrow">Built for shared expenses</span>
            <h2 id="security-title">Useful to your group.<br />Not an ad profile.</h2>
          </div>
          <div className="security-receipt">
            <p><span>01</span><strong>Sign in securely</strong><small>Your session identifies you; Cleave never asks support users for a password.</small></p>
            <p><span>02</span><strong>Share intentionally</strong><small>Collaborative receipt details are available to that receipt’s group members.</small></p>
            <p><span>03</span><strong>Stay in control</strong><small>Adjust profile visibility, leave groups, delete admin receipts, or delete your account.</small></p>
          </div>
        </section>
      </main>
    </SiteShell>
  );
}
