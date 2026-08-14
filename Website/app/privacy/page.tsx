import type { Metadata } from "next";
import { SiteShell } from "../site-shell";

export const metadata: Metadata = {
  title: "Privacy Policy | Cleave",
  description: "How Cleave collects, uses, shares, retains, and protects your information.",
};

const sections = [
  {
    id: "information",
    number: "01",
    title: "Information we collect",
    content: (
      <>
        <p>We collect information you choose to provide and information needed to operate Cleave:</p>
        <ul>
          <li><strong>Account and profile:</strong> email address, unique username, display name, account identifier, non-exact age range, region, optional profile photo, profile visibility choices, and optional Venmo, Google Pay UPI, or Aani payment handles.</li>
          <li><strong>Groups and collaboration:</strong> group names, membership, invitations, inbox activity, receipt administrators, and friend connections derived from people in your shared collaborative groups. Cleave does not upload your address book.</li>
          <li><strong>Receipt and purchase information:</strong> receipt images, merchant names, line items, original receipt currency, amounts, tax, tip, discounts, individual claims, admin corrections, balances, payment-status confirmations, ratings, and optional memory photos.</li>
          <li><strong>Technical information:</strong> security and service logs such as request identifiers, IP address, timestamps, and error details generated when you use our online services.</li>
        </ul>
        <p>Local, non-collaborative groups and manually entered receipts can remain in an account-scoped cache on your device. If you scan a receipt, its image is sent to our service and Google Gemini for extraction even when the resulting split is local. Cleave does not collect your bank password or move money itself.</p>
      </>
    ),
  },
  {
    id: "use",
    number: "02",
    title: "How we use information",
    content: (
      <>
        <p>We use information to authenticate you, create your profile, apply your visibility choices, operate local and collaborative groups, parse receipts, calculate and reconcile splits, show balances in the receipt’s original currency, synchronize devices, deliver group activity, provide support, secure the service, diagnose errors, and improve reliability.</p>
        <p>We do not sell personal information. We do not use your information for targeted advertising or track you across other companies’ apps and websites.</p>
      </>
    ),
  },
  {
    id: "sharing",
    number: "03",
    title: "Sharing and service providers",
    content: (
      <>
        <p>We share information only as needed to provide Cleave:</p>
        <ul>
          <li><strong>Other group members</strong> can see collaborative group data, receipts, claims, assignments, balances, payment status, ratings, memories, and profile details made available to that group. Your photo and payment-handle visibility settings further control those profile fields.</li>
          <li><strong>Supabase</strong> provides authentication and database infrastructure.</li>
          <li><strong>Google Cloud</strong> hosts Cleave’s backend, private media storage, and operational logs.</li>
          <li><strong>Google Gemini</strong> receives receipt images and a parsing instruction to extract receipt details.</li>
          <li><strong>Apple</strong> processes information when you use Sign in with Apple or App Store services under Apple’s own terms.</li>
          <li><strong>Payment apps</strong> such as Venmo, Google Pay, or Aani receive the recipient, amount, and payment note only when you choose to open that app. Their own terms and privacy policies apply.</li>
        </ul>
        <p>These providers process information on our behalf or under their own applicable terms. We may also disclose information when required by law, to protect people or the service, or as part of a business transfer, subject to appropriate safeguards.</p>
      </>
    ),
  },
  {
    id: "storage",
    number: "04",
    title: "Storage, security, and retention",
    content: (
      <>
        <p>Collaborative app records are stored in a protected database. Receipt images, profile photos, and memory photos are kept in private cloud storage and are returned only after the service checks access. Cleave uses encrypted network connections, authenticated API requests, role and membership checks, restricted database access, private object storage, request limits, and file validation.</p>
        <p>We retain account and collaborative content while your account is active or as needed to operate the service. When an authorized receipt admin deletes a receipt, or you delete your account, Cleave removes the corresponding live records and media that it controls. Provider backups and security or operational logs may remain until they expire under provider schedules, or longer where needed for legal, security, fraud-prevention, or dispute-resolution purposes. No security method is guaranteed to be perfect.</p>
      </>
    ),
  },
  {
    id: "choices",
    number: "05",
    title: "Your choices and deletion",
    content: (
      <>
        <p>You can update your display name, unique username, profile photo, payment handles, age range, region, and visibility choices in the app. Camera and photo-library access can be changed in iOS Settings. You can leave groups, and a receipt admin can delete a receipt they scanned. You can sign out at any time.</p>
        <p>To permanently delete your account, open <strong>Cleave → Settings → Delete Account</strong>. This removes your authentication account, profile, content owned by the account, associated live receipt records and uploaded media that Cleave controls, and the account’s local cache. Shared content controlled by another user may remain where needed to preserve that user’s records or rights.</p>
        <p>You can also request help with access, correction, deletion, or another privacy question by emailing <a href="mailto:cleave.receipts@gmail.com">cleave.receipts@gmail.com</a>. We may need to verify your identity before fulfilling a request.</p>
      </>
    ),
  },
  {
    id: "children",
    number: "06",
    title: "Children and international processing",
    content: (
      <>
        <p>Cleave is not directed to children under 13, and we do not knowingly collect personal information from children under 13. If you believe a child provided information, contact us so we can investigate and delete it where appropriate.</p>
        <p>Our providers may process information in countries other than where you live. Those countries may have different data-protection laws. We use safeguards appropriate to the service and applicable law.</p>
      </>
    ),
  },
  {
    id: "changes",
    number: "07",
    title: "Changes and contact",
    content: (
      <>
        <p>We may update this policy as Cleave changes. We will post the revised policy here and update the effective date. If a change materially affects your rights, we will provide additional notice when appropriate.</p>
        <p>Questions about Cleave or this policy can be sent to <a href="mailto:cleave.receipts@gmail.com">cleave.receipts@gmail.com</a>.</p>
      </>
    ),
  },
];

export default function PrivacyPage() {
  return (
    <SiteShell>
      <main className="document-page">
        <header className="document-hero">
          <div className="eyebrow">Legal · Plain language</div>
          <h1>Privacy policy</h1>
          <p>We built Cleave to make shared expenses simpler—not to turn your receipts into an advertising profile.</p>
          <div className="effective-date"><span>Effective</span><strong>August 14, 2026</strong></div>
        </header>

        <div className="document-layout">
          <aside className="toc" aria-label="On this page">
            <p>On this page</p>
            {sections.map((section) => <a key={section.id} href={`#${section.id}`}>{section.number} {section.title}</a>)}
          </aside>
          <article className="policy-content">
            <section className="policy-intro">
              <p>This Privacy Policy explains how Cleave (“we,” “us,” or “our”) handles information when you use the Cleave iOS app, website, and related services.</p>
            </section>
            {sections.map((section) => (
              <section className="policy-section" id={section.id} key={section.id}>
                <span className="section-number">{section.number}</span>
                <div><h2>{section.title}</h2>{section.content}</div>
              </section>
            ))}
            <div className="legal-note">This policy describes the current Cleave service and is not a substitute for legal advice.</div>
          </article>
        </div>
      </main>
    </SiteShell>
  );
}
