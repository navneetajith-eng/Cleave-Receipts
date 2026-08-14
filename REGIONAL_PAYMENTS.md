# Cleave regional payments decision

Research checked: August 11, 2026.

## Decision

| Region | Currency | Cleave handoff | Why |
| --- | --- | --- | --- |
| United States | USD | Venmo | The existing user flow already uses Venmo, and personal payments are widely supported. |
| India | INR | Google Pay using UPI | UPI is interoperable and Google publishes an iOS app-switch scheme. |
| United Arab Emirates | AED | Aani | Aani is the UAE national instant-payment platform operated by Al Etihad Payments, a Central Bank of the UAE subsidiary. |

Cleave uses an app handoff, not an embedded payment processor. Cleave calculates the amount, prepares the recipient where a usable handoff exists, and opens the payment app. The payment app remains responsible for recipient verification, authorization, fees, and transaction status.

This design adds no paid SDK, API, merchant account, or per-transaction Cleave cost.

## Why an embedded integration was rejected

- The official Venmo merchant integration runs through Braintree, uses normal processing pricing, and explicitly lists facilitating peer-to-peer payments between Venmo users as unsupported. See [Braintree's Venmo eligibility and fees](https://developer.paypal.com/braintree/articles/guides/payment-methods/venmo/).
- Google's official India in-app UPI flow is a merchant flow. It requires a verified UPI merchant, merchant VPA, merchant category code, bank APIs, and transaction-status verification. See [Google Pay India prerequisites](https://developers.google.com/pay/india/api/android/overview) and the [iOS intent format](https://developers.google.com/pay/india/api/ios/in-app-payments).
- Aani's public consumer documentation describes payments through Aani and participating bank apps, but the reviewed official documentation does not publish a consumer iOS payment URL or public developer API. See [Al Etihad Payments' Aani overview](https://aep.ae/en/services/aani/) and [customer FAQ](https://aep.ae/en/frequently-asked-questions/customers/).

Using any of those merchant/processor paths would make the promise of a universally free settlement flow inaccurate. It would also turn Cleave into a more payment-sensitive system requiring transaction reconciliation, provider onboarding, support, and additional compliance review.

## Fee reality

Cleave charges nothing for the handoff, but it cannot guarantee that every funding source or bank choice is free:

- Venmo lists personal payments funded by balance, debit card, or bank account at $0. A credit-card-funded personal payment is 3%, and goods/services or business payments have recipient fees. See [Venmo's official fee schedule](https://venmo.com/legal/fees/).
- NPCI says UPI customers are not charged for the UPI transactions described in its FAQ. Google also says it adds no Google Pay API fee, while ordinary processor fees may still exist in merchant flows. See the [NPCI UPI FAQ](https://www.npci.org.in/what-we-do/upi/faqs) and [Google Pay FAQ](https://developers.google.com/pay/api/faq).
- Aani is free to download. Some banks explicitly describe their Aani consumer transfers as free, but participating institutions can have their own terms or limits. See [Aani on the App Store](https://apps.apple.com/ae/app/aani/id6444847879) and [HSBC UAE's Aani terms summary](https://www.hsbc.ae/money-transfers/aani/).

The app therefore says that Cleave itself charges no settlement fee and tells the user to review the provider's final screen.

## What remains realistic, and what does not

Realistic now:

- Exactly three selectable regions and currencies.
- Region automatically selects the displayed currency and settlement app.
- Venmo recipient, amount, and note handoff when the installed Venmo version accepts its legacy URL scheme, with App Store fallback.
- Google Pay handoff with UPI ID, recipient name, INR amount, and note using Google's documented iOS `gpay://upi/pay` URI shape.
- Aani App Store handoff with copied amount and no Aani details requested.
- Only payment aliases (Venmo username or UPI ID) are stored. Cleave never stores bank credentials, cards, PINs, or payment-app passwords.
- No new backend dependency and no paid integration.

Not available in the zero-cost handoff:

- Cleave cannot confirm whether a payment completed, failed, was canceled, or was sent to the wrong person.
- Google documents the iOS UPI URI as an in-app merchant flow. Cleave uses its URI structure only as a user-confirmed app handoff; it does not claim merchant status, receive a callback, or mark a balance paid. Google Pay can change or reject this behavior.
- Venmo does not currently publish a supported consumer deep-link contract for this use. Its legacy scheme may ignore fields or change, so the final Venmo screen must always be verified.
- Aani does not publish a consumer iOS deep-link/API contract. It can only be opened through its store page from this zero-cost integration.
- Aani users must be enrolled through Aani or a participating UAE financial institution.

## Data-model risk

The existing receipt and group models store amounts as plain numbers without a currency or region. Calculations will not break, but changing the global region will relabel historical amounts instead of converting or preserving their original currency. For example, an old value of `100` can display as `$100`, `₹100`, or `AED 100` after a settings change.

That behavior matches the current global-settings architecture, but a production app used across travel or mixed-region groups should add an immutable region/currency field to each group or receipt. Existing records would need a one-time default during migration. Currency conversion should not be added implicitly because it would alter debt amounts and require exchange-rate data, rounding rules, and a paid or rate-limited data source.

## Security boundary

- Cleave never asks for a bank login, UPI PIN, card number, Venmo credential, or Aani credential.
- The handoff never marks a balance paid.
- The user is told to verify recipient and amount in the payment app.
- Payment app availability and eligibility remain country-, bank-, and account-dependent.
- Payment aliases are returned only on the authenticated user's own profile and to authenticated members of the same group. Public profile search and the friends endpoint omit them.
