import type { Metadata } from "next";
import Link from "next/link";
import { SiteShell } from "../site-shell";

export const metadata: Metadata = {
  title: "Support | Cleave",
  description: "Help with Cleave accounts, collaborative groups, receipt scanning, and privacy.",
};

const topics = [
  ["Account & profile", "Display names, unique usernames, privacy controls, handles, and deletion."],
  ["Groups & friends", "Collaboration, invites, friend profiles, leaving, and receipt admins."],
  ["Receipts & claims", "Scanning, drafts, individual item claims, admin review, and corrections."],
  ["Balances & payments", "Tax, tip, discounts, currency, rounding, payment apps, and confirmation."],
];

const faqGroups = [
  {
    title: "Account, profile & privacy",
    questions: [
      ["What is the difference between my display name and username?", "Your display name is the friendly name shown throughout receipts and groups. Your unique username identifies your account for search and invitations, so no two accounts can use the same one."],
      ["Why does Cleave ask for an age range and region?", "Cleave uses a non-exact age range to enforce its 13+ requirement without asking for your birth date. Region helps show relevant payment methods and defaults. Replaying onboarding lets you review these choices without signing in again."],
      ["Who can see my profile photo and payment handles?", "You choose private, shared groups only, or everyone for these fields. Your display name and username remain visible where needed so group members can identify claims and balances."],
      ["How are friends created, and does Cleave read my contacts?", "Friends are people you share a collaborative group with. Cleave does not upload your phone contacts. Tap a friend to see the profile details they have chosen to make visible to you."],
      ["How do I delete my account?", "Open Settings → Delete Account and confirm. This is permanent. If you cannot access the app, email support from the address associated with the account so we can verify the request."],
    ],
  },
  {
    title: "Groups, receipts & individual claims",
    questions: [
      ["Who is the receipt admin?", "The person who scans or manually creates that receipt is its admin. Creating the group does not make someone admin of every receipt."],
      ["Who chooses the items?", "Each participant selects their own items. The receipt admin can also claim their share, see who has selected each item, correct allocations when needed, and complete review after everyone is done."],
      ["What does Pending mean?", "Pending means that participant has not finished choosing their items. The summary updates as each person submits their own claim."],
      ["What if two identical items belong to different people?", "Open the item picker and check the participant indicators already shown on each line. This helps distinguish, for example, two separate burgers even when their names and prices match."],
      ["Can anyone delete a group or receipt?", "Nobody deletes a group from the normal group flow; each member can leave it. Only the admin of a particular receipt can delete that receipt, with confirmation."],
      ["What happens if I leave halfway through scanning?", "Cleave keeps a device draft when it can so an interrupted scan is not silently lost. You can retry or intentionally discard it. A dismissed error should not reappear every time you reopen the app."],
      ["Can I enter or correct a receipt manually?", "Yes. Use the group’s always-available add receipt action, choose manual entry, and review merchant, items, quantities, currency, tax, tip, discount, and total before continuing."],
    ],
  },
  {
    title: "Calculations, currency & payments",
    questions: [
      ["How are tax, tip, and discounts divided?", "Cleave allocates them proportionally based on each participant’s claimed item subtotal. The breakdown shows items, tax, tip, discount, and final total rather than only one number."],
      ["Why can totals differ by one cent?", "Currency cannot be split below its smallest unit. Cleave uses deterministic rounding so the participant totals still add back to the receipt total."],
      ["What if group members use different currencies?", "Every receipt keeps the currency printed on that receipt. Cleave does not silently convert debts or invent an exchange rate. Participants should agree on a payment currency and rate outside the app; the recorded balance remains in the original receipt currency."],
      ["Does Cleave move or hold money?", "No. Cleave calculates what is owed and can open a compatible payment app with payment details. The payment is completed in that third-party app, subject to its fees, availability, terms, and privacy policy."],
      ["What is the difference between sent, pending, and confirmed?", "A participant marks that they sent payment. It becomes pending until the receipt admin checks the payment app and confirms or rejects it. Cleave does not read your bank or payment-app transaction history."],
      ["Can an admin owe money too?", "Yes. The admin participates like everyone else and sees their own item, tax, tip, discount, and total breakdown. Their extra powers are limited to receipt review, corrections, payment confirmation, and receipt deletion."],
    ],
  },
  {
    title: "Scanning, moments & security",
    questions: [
      ["How do I get the best scan?", "Place the full receipt on a flat surface in bright, even light. Avoid glare, folds, fingers, and cropped totals. Cleave validates the image, sends it securely for parsing, and asks you to review the result before saving."],
      ["What happens to a scanned receipt image?", "The image is sent to Cleave’s backend and Google Gemini to extract receipt details. Collaborative receipt images and other media are stored privately and served only after access checks."],
      ["Who can add ratings and memories?", "Each receipt participant can add their own rating and optional photo. The receipt’s Moments view groups ratings and photos with the person who added them."],
      ["What should I send support?", "Include your iOS version, the screen you were on, the approximate time, and steps to reproduce the issue. Screenshots are helpful after you hide sensitive receipt or payment details. Never send your password or authentication code."],
      ["Is Cleave impossible to hack?", "No connected service can honestly promise that. Cleave reduces risk with authenticated requests, authorization checks, private storage, restricted database access, upload validation, request limits, encrypted connections, and ongoing dependency and configuration reviews."],
    ],
  },
];

export default function SupportPage() {
  return (
    <SiteShell>
      <main className="support-page">
        <section className="support-hero">
          <div>
            <div className="eyebrow">Cleave support</div>
            <h1>How can we<br />help?</h1>
            <p>Tell us what happened and we’ll help you get back to splitting.</p>
          </div>
          <a className="email-card" href="mailto:cleave.receipts@gmail.com?subject=Cleave%20Support%20Request">
            <span>Email support</span>
            <strong>cleave.receipts@gmail.com</strong>
            <small>Include your iOS version and what you were doing when the issue occurred. Never send your password.</small>
            <b aria-hidden="true">↗</b>
          </a>
        </section>

        <section className="faq-section" aria-labelledby="faq-title">
          <div className="section-heading faq-heading">
            <div><span>Frequently asked questions</span><h2 id="faq-title">The full flow, explained.</h2></div>
            <p>Tap a question to open it.</p>
          </div>
          <div className="faq-groups">
            {faqGroups.map((group, groupIndex) => (
              <section className="faq-group" key={group.title}>
                <div className="faq-group-title"><span>0{groupIndex + 1}</span><h3>{group.title}</h3></div>
                <div className="faq-list">
                  {group.questions.map(([question, answer]) => (
                    <details key={question}>
                      <summary><span>{question}</span><b aria-hidden="true">+</b></summary>
                      <p>{answer}</p>
                    </details>
                  ))}
                </div>
              </section>
            ))}
          </div>
        </section>

        <section className="topic-section">
          <div className="section-heading"><span>Common topics</span><p>Choose the closest category when describing your issue.</p></div>
          <div className="topic-grid">
            {topics.map(([title, description], index) => (
              <article className="topic-card" key={title}>
                <span>0{index + 1}</span><h2>{title}</h2><p>{description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="support-details">
          <article>
            <div className="mini-label">Account deletion</div>
            <h2>You can delete your account in Cleave.</h2>
            <p>Open <strong>Settings → Delete Account</strong> and confirm. The action is permanent. If you cannot access the app, email us from the address associated with your account.</p>
          </article>
          <article>
            <div className="mini-label">Privacy</div>
            <h2>Your data, explained clearly.</h2>
            <p>Read what Cleave collects, why it is needed, which providers help us operate, and how to make a privacy request.</p>
            <Link className="text-link" href="/privacy">Read the privacy policy <span>→</span></Link>
          </article>
        </section>

        <section className="response-note">
          <span className="pulse" aria-hidden="true" />
          <p><strong>We’re a small team.</strong> We aim to respond to support and privacy emails within two business days. Never include a password or authentication code.</p>
        </section>
      </main>
    </SiteShell>
  );
}
