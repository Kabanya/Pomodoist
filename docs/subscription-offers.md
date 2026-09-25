# Subscription trials and return campaigns

## Terms

Keep subscription group `22266202` and both existing product identifiers.
The following are the **target US storefront prices**, not a statement that
App Store Connect has been changed. Apple supplies localized prices in other
territories; the client displays StoreKit's currency and offer metadata.

| Product | Introductory offer | Regular renewal | Return campaign |
| --- | --- | --- | --- |
| `pomodoist.pro.monthly` | 7 days free | USD 4.99/month | USD 1.99/month for 3 months, then USD 4.99/month |
| `pomodoist.pro.annual` | 7 days free | USD 29.99/year | USD 14.99 for one year, then USD 29.99/year |

The annual regular price is 49.9% lower than twelve monthly payments.
Apple grants at most one introductory offer per subscription group; switching
plans does not create another trial. A return offer does not include a trial.
The offer's paid periods automatically renew at the regular price unless
cancelled. Lifetime products are unchanged.

Campaign `return-2026-v1` uses promotional offer identifiers:

- Monthly: `return_monthly_2026_v1`, pay as you go, one month × 3.
- Annual: `return_annual_2026_v1`, pay up front, one year × 1.

Eligibility starts exactly seven elapsed days after the latest actual,
non-revoked subscription/trial expiry, using server time and verified Apple
history. Turning off auto-renewal does not start that clock. Active Pro,
lifetime, grace, billing retry, family-shared purchases, and a previously
redeemed campaign are excluded. A refund does not replenish the campaign.
There is one campaign across the two subscription products and subscription
chains for the verified Apple customer. The offer appears in the shared Pro
paywall when the customer returns; there are no campaigns by email, push,
browser, code, or automatic reminder.

## Purchase and verification

`StoreKitHost.latestSubscriptionTransaction` supplies a verified Apple JWS,
including an expired subscription. This read never grants access. The
`pomodoist-subscription-offer` function verifies the seed and requests complete,
paginated App Store Server API history plus subscription statuses, verifying
each transaction and renewal JWS. It uses Apple's signed `appTransactionId`
from fresh history to identify the customer across subscription chains.
Missing or inconsistent identity/history fails closed.

The endpoint does not require a Pomodoist account. If signed in, account-token
and existing purchase ownership checks additionally restrict eligibility.
An accountless request cannot supply an invented app-account token. The server signs an ES256 promotional-offer JWS with mandatory `transactionId`
set to the authoritative Apple `appTransactionId`, so Apple restricts redemption
to that customer. The optional Pomodoist account token is passed to the native
purchase for existing account linking.

The installed StoreKit plugin supports only the legacy promotional signature,
which cannot bind the Apple customer and is silently omitted by the plugin on
iOS before 17.4/macOS before 14.4. To satisfy the identity and no-fallback
requirements, the small existing native bridge now purchases the JWS offer via
`Product.PurchaseOption.promotionalOffer(_:compactJWS:)`. Xcode 26 back-deploys
this API to iOS 15/macOS 12. No plugin fork or new dependency is needed. The
result becomes the plugin's `SK2PurchaseDetails`; catalog, asynchronous updates,
completion, restore, entitlement verification and account linking continue
through the existing plugin/controller flow. Build with Xcode 26 or newer.

The private SQL ledger has one row per environment, Apple customer and campaign.
A row lock serializes competing requests across products. Issuing a signature
reserves the campaign; it does not record redemption. Verified history,
purchase ingestion, or Apple server notifications permanently record actual
redemption. The client cannot clear or mark this ledger.

**Cancellation retry boundary:** a nonce must not be reused for another
purchase attempt, and there is no server API to revoke an issued signature.
Cancellation does not consume the discount. Another signature is withheld for
the configured, Apple-confirmed **maximum JWS lifetime plus five minutes**.
The paywall displays the server's retry date. A timeout after signature
issuance can have the same reservation consequence. There is no client
cancellation/unlock endpoint.

Apple's JWS documentation derives expiry from `iat`, forbids `exp`, and does
not publish a numeric maximum. The legacy 24-hour lifetime is not treated as
proof for JWS. Consequently `APPLE_RETURN_OFFER_SIGNATURE_MAX_AGE_SECONDS` has
**no default**, must be confirmed with Apple before activation, and is required
to enable the endpoint. Tests use 86400 seconds as an injected fixture, not a
claim about Apple's V2 lifetime. Missing/invalid configuration fails closed.
Fresh Apple history and the permanent redemption ledger are still checked
after a reservation ends; no fixed interval guarantees instant external
transaction propagation.

A discount checkout failure never starts an ordinary purchase. Subscription
buttons are blocked while eligibility is loading, has failed, or has a pending
reservation. The user can retry the server check; the screen does not turn
that action into ordinary checkout. Intentional campaign disablement returns
an ordinary ineligible response and does not display an error. Promotional metadata must match the campaign's actual
billing periods before the client displays or purchases it. Trial text uses
the period returned by Apple, so an older paid introduction continues to be
shown correctly before the rollout date.

The signature binds the SKU, offer and verified Apple customer; it must not be
logged or shared. The production signer accepts Production proofs only by
default. Sandbox acceptance requires a separate private test signer and a
dedicated test key, disabled/revoked after testing. Apple controls signature
expiry and history propagation, so full history checks and a database lock
cannot make the external Apple purchase and local ledger one atomic operation.

## Server configuration

Apply migration `20260913203151_pomodoist_subscription_offers.sql` before deploying
`pomodoist-subscription-offer`. The function is configured with `verify_jwt = false`
so accountless users can call it, but verifies Apple proofs itself and validates
any supplied user session. Only `service_role` can access the ledger and its RPC.
The self-hosted function router discovers the function directory; Compose
forwards its environment variables.

Required server secrets (never Flutter defines or source control):

- `APPLE_IAP_KEY_ID`: Apple In-App Purchase key ID.
- `APPLE_IAP_ISSUER_ID`: associated issuer ID.
- `APPLE_IAP_PRIVATE_KEY`: matching PKCS#8 PEM; escaped newlines are accepted.
- `APPLE_RETURN_OFFERS_ENVIRONMENT`: `Production` by default; `Sandbox` only
  on a private test deployment.
- `APPLE_RETURN_OFFERS_ENABLED`: `false` until the rollout gate below passes.
- `APPLE_RETURN_OFFER_SIGNATURE_MAX_AGE_SECONDS`: Apple-confirmed upper bound
  for the V2 signature lifetime, in seconds (1–604800). No default. The ledger
  adds five minutes; do not infer this value from legacy signature docs.

Use a key with App Store Server API and promotional-offer signing privileges;
an arbitrary App Store Connect upload key is not assumed to have them.
An intentionally disabled campaign returns ordinary ineligibility. If the
campaign is enabled but credentials or the confirmed lifetime bound are
missing, verification fails closed. The ordinary Apple
purchase flow remains available. Configure existing App Store notifications
for both purchase lifecycle and durable redemption updates.

## Read-only App Store Connect check

Verified by authenticated GET requests on **2026-09-13 UTC**:

| Product | ASC ID | Status | Current US regular price | Current US introduction |
| --- | --- | --- | --- | --- |
| Monthly | `6794893527` | APPROVED | USD 5.99 | Pay as you go, one month × 3 |
| Annual | `6794894380` | APPROVED | USD 39.00 | Pay up front, one year × 1 |

Both US price lists contained one current price and no future scheduled price.
Both introductions started 2026-07-26 with no end date. No promotional offers
were configured. Published versions included 1.0.5 for iOS and macOS. This
snapshot is specific to the US queries; re-read all selected territories and
pending schedules immediately before changing them. No live Apple mutation,
server deployment, app upload/publication, or offer activation is part of the
local implementation verification.

## Rollout gates

1. Re-read existing subscription status, all affected territory prices,
   introductory schedules, and promotional offers. Retain the existing SKUs
   and group. Resolve overlaps before replacing the paid introductions.
2. Deploy the migration and function with offers disabled; install the IAP
   signing key. Verify existing purchase and notification ingestion continues.
3. Prepare the two promotional offers and the seven-day trial in App Store
   Connect. Coordinate their availability with the compatible client. Use a
   private Sandbox server for manual purchase acceptance; do not shorten the
   production seven-day threshold just to accommodate accelerated renewals.
4. The user manually accepts iOS and macOS Sandbox: displayed/Apple-sheet
   currency and prices, eligible trial, expired trial and paid return, the
   seven-day boundary, restoration, cancellation, errors, concurrent attempts,
   already-used campaign, lifetime/grace/retry exclusion, and accountless
   purchase. Local `.storekit` data tests metadata but cannot prove Apple's
   server history or production signing. For a full return test, use an account
   whose real Sandbox expiry is at least seven days old. Clock injection in
   unit tests is not a production or deployed Sandbox override.
5. Confirm the V2 JWS maximum lifetime with Apple, configure
   `APPLE_RETURN_OFFER_SIGNATURE_MAX_AGE_SECONDS`, and test retry after the
   reservation expires. Do not activate the campaign until that cancellation/concurrency
   boundary is accepted.
6. **Separately confirm application publication.** Ship the compatible iOS and
   macOS builds and verify public availability, not merely upload/processing.
7. **Separately confirm price changes** to USD 4.99/29.99 and their local
   equalizations. Set the agreed effective date after client availability.
   Price decreases also affect existing subscribers' next renewals; they are
   not grandfathered at the old higher price.
8. **Separately confirm offer activation:** replace introductions with the
   seven-day trial at the agreed date and enable the return campaign only
   after matching StoreKit metadata, server readiness, and public client
   availability are confirmed. Re-read ASC to confirm applied settings.

Emergency disablement stops issuing new signatures. Existing issued signatures
remain valid until expiry; already purchased subscriptions retain their terms.

## Automated checks

Implementation verification: 55 Flutter unit tests, 44 Deno tests (69 steps),
full Flutter analysis, iOS 15/macOS 12 Swift type checks, localization contracts,
and real isolated SQL ACL/lease/concurrency checks passed. No app was launched
for manual acceptance and no live deployment or Apple write was performed.

From the repository root:

```sh
cd apps/flutter
../../.fvm/flutter_sdk/bin/flutter gen-l10n
../../.fvm/flutter_sdk/bin/flutter analyze --no-pub
../../.fvm/flutter_sdk/bin/flutter test --no-pub test/billing_offers_test.dart test/billing_storekit_test.dart test/billing_storekit_bridge_test.dart test/billing_access_tier_test.dart
cd ../..
python3 tool/check_localization.py
cd server
deno test --allow-read --config supabase/deno.json supabase/functions/pomodoist-subscription-offer/ supabase/functions/pomodoist-app-store-notifications/ supabase/functions/pomodoist-purchase/
```

The SQL role/ledger/concurrency check uses a disposable database in an explicitly
selected local test Postgres container:

```sh
server/tests/database/subscription_offers_check.sh pomodoist-selfhost-LOCAL_TEST_CONTAINER
```

Manual UI, signed Sandbox transactions and a production launch remain separate
acceptance steps. Unit tests use generated test keys and injected Apple responses;
they do not demonstrate that an operational IAP key has been installed.

## Stripe — 1.1.0 rollout

All 1.1.0 client flavors understand the versioned Stripe offer catalog. The
server controls activation with `STRIPE_SUBSCRIPTION_OFFERS_ENABLED=true`;
its default remains false. Use `STRIPE_BILLING_ENVIRONMENT=production` with a
live key, or `develop` with a test key. Prices, coupons, customers, subscription
and invoice history, Checkout sessions and webhook events must match that mode.
The previous `STRIPE_TEST_SUBSCRIPTION_OFFERS_ENABLED` flag remains supported
for existing development deployments and still rejects live keys.

Deploy the reservation migration and compatible functions before activation,
and publish the compatible web client before enabling the production catalog.
Reuse the existing production product with new USD 4.99/month and 29.99/year
prices and production return coupons (USD 3 off for three months; USD 15 off
once for annual). Never copy test object IDs or a test webhook secret to live.
Existing Stripe subscriptions keep their current prices; this rollout does not
rewrite customer subscriptions or create prorations. Existing open Checkout
sessions block a second checkout until they finish or expire.

A 1.1.0 client also accepts the disabled-offer legacy catalog. Older clients
without `offerVersion=1` receive `billing_update_required` after offer activation;
the server never silently substitutes regular pricing for a requested offer.
Activation status must be checked against the deployed environment separately
from tests and code publication.

The USD terms match the table above. Stripe uses its own authenticated Pomodoist
account/customer history, not Apple's anonymous purchase identity or signatures.
The trial is once across monthly and annual subscriptions for this customer;
a canceled zero-value trial still counts. A return purchase has no trial.
Eligibility starts seven complete days after Stripe `ended_at`, not
`canceled_at` (which can mark a scheduled cancellation before access ends).
Active Pro/lifetime and any nonterminal Stripe status, including dunning,
unpaid, incomplete and paused, block checkout. All history pages are read.
A paid return invoice consumes campaign `return_2026_v1` across both plans;
refunds do not reset it. Credits covering an otherwise nonzero invoice also
count as payment. Stripe's retained subscription/invoice history is the
redemption record; the application does not trust a client clock or flag.

Checkout receives the selected offer and revalidates it. Changed eligibility,
API/configuration failures and concurrent attempts return an error instead of
falling back to full price. The server applies coupons directly; there are no
user-entered codes. Payment still uses the existing hosted Stripe Checkout and
requires a Pomodoist account. Apple continues to use native StoreKit without a
mandatory account. Stripe's USD catalog does not reproduce Apple's storefront
price equalization; Checkout determines applicable taxes and any supported
currency conversion. Verify the final presented currency/total during acceptance.

The shared Pro paywall reuses existing localized trial and return-offer copy.
There are no new notifications or campaigns. Before sign-in/catalog verification,
the paywall does not advertise an unverified Stripe price. Shared fallback
subscription prices are USD 4.99/month and USD 29.99/year. The older paid
introduction and USD 5.99/39 catalog remain only in the disabled-offer legacy
path for existing production configuration; development never displays that
paid introduction.

### Prepared test catalog

Verified against Stripe on 2026-09-24; every object has `livemode=false`.
Existing test product `prod_V0Os8ESsMYYxOx` is reused. Old prices/coupons remain
untouched, so this does not change existing subscribers.

| Server variable | Test object | Terms |
| --- | --- | --- |
| `STRIPE_PRICE_MONTHLY` | `price_1UIzUjK42TpBP1F46UQARy9h` | USD 4.99/month |
| `STRIPE_PRICE_ANNUAL` | `price_1UIzUlK42TpBP1F4Caf8B7O3` | USD 29.99/year |
| `STRIPE_COUPON_MONTHLY_RETURN` | `pomodoist_develop_return_2026_month` | USD 3 off, repeating 3 months |
| `STRIPE_COUPON_ANNUAL_RETURN` | `pomodoist_develop_return_2026_year` | USD 15 off, once |

Identifiers and flags are also saved in the ignored local file
`server/.env.stripe-offers.develop` (mode 0600; it may contain credentials).
The file is not loaded automatically. Apply test values only to the development
backend, and never commit or copy the file into production.

### Development setup and acceptance

1. Apply migration `20260923234807_pomodoist_core_stripe_test_offers.sql` to the
   **development** database through the normal migration runner. Never edit the
   consolidated initial schema. The private reservation table and service-only
   RPCs serialize all Checkout products for an account.
2. Configure the development functions with the test key, development webhook
   secret, all existing lifetime price IDs, the four values above,
   `STRIPE_BILLING_ENVIRONMENT=develop`,
   `STRIPE_TEST_SUBSCRIPTION_OFFERS_ENABLED=true` and
   `STRIPE_CHECKOUT_ENABLED=true`. Keep the existing Managed Payments setup.
   In Compose, `SITE_URL` supplies Checkout return URLs; it must point to the
   development client. No remote deployment was performed by this preparation.
3. Route test Stripe events to the development `stripe-webhook` function.
   Subscribe to subscription created/updated/deleted, Checkout completed/async
   payment succeeded, invoice paid/payment failed and charge refunded events.
   Verify the signature with that endpoint's secret, not a live endpoint secret.
4. Run the development client with `POMODOIST_BILLING_CHANNEL=stripe` and
   `POMODOIST_DEV_UNLOCK=false`. Catalog and Checkout carry `offerVersion: 1`;
   older clients are rejected while test offers are enabled. Sign in to view
   verified offers. Eligibility does not grant Pro; verified webhooks do.
5. Manually accept the complete test flow: both trial plans, trial cancellation
   and expiry, regular renewal, return after seven elapsed days, all three
   monthly discount invoices / one annual discount invoice, regular renewal
   afterward, restoration after sign-in, dunning/lifetime exclusions, cancellation,
   account switch, concurrent devices and verification failures. A Stripe test
   clock does not override the application's wall clock; test the boundary with
   unit fixtures or genuinely elapsed history.

**Cancellation/concurrency:** one account-wide SQL reservation stores immutable
Checkout parameters and anchors a 40-minute session expiry. Identical retries
reuse the open session/Stripe idempotency key. Closing the browser does not
consume the offer. Selecting another product waits for the old session to
expire; retry then releases it after Stripe verification. A completed payment
that is still processing remains blocked. Completed sessions are released only
when fresh history permits another purchase. Legacy open/processing sessions
also block the transition. These checks fail closed if Stripe is unavailable.

### Verification performed

Current checks passed: 32 Flutter unit tests, 29 Deno tests, full Flutter
analysis, Deno entry-point checks, architecture boundaries and localization
contracts. No app was launched for manual acceptance.

- Stripe's real test API accepted all four Managed Payments Checkout requests:
  monthly/annual trial totals were USD 0; monthly return total USD 1.99 and annual
  return total USD 14.99. Each test session was explicitly expired without a
  payment. This proves parameter/catalog compatibility, not renewals or webhook
  delivery.
- Unit coverage checks the seven-day boundary, canceled trials, shared campaign
  reuse, exact prices/coupon duration, live-key isolation, selected-offer mismatch,
  API errors, immutable retry parameters, concurrent plans, cancellation and
  processing payments. Webhook tests include trial access and live-event rejection.
- An isolated disposable PostgreSQL database verifies migration execution,
  client-role denial, concurrent cross-product reservations and stale-release
  protection. No running application database was changed.

Reproduce from the repository root:

```sh
deno test --config server/supabase/deno.json server/supabase/functions/pomodoist-stripe-billing/ server/supabase/functions/stripe-webhook/
bash server/tests/database/stripe_offers_check.sh pomodoist-selfhost-db
cd apps/flutter
../../.fvm/flutter_sdk/bin/flutter test --no-pub test/stripe_subscription_offers_test.dart test/data/billing_access_repository_test.dart test/billing_offers_test.dart
../../.fvm/flutter_sdk/bin/flutter analyze --no-pub
```

Public release, live Stripe configuration and Apple offer activation remain
separate release decisions. Do not enable test configuration in a published build.

Stripe references: [Checkout trials](https://docs.stripe.com/payments/checkout/free-trials),
[coupon durations](https://docs.stripe.com/billing/subscriptions/coupons#coupon-duration),
[Checkout expiry](https://docs.stripe.com/api/checkout/sessions/create#create_checkout_session-expires_at).

## Apple references

- [Promotional offer implementation](https://developer.apple.com/documentation/storekit/implementing-promotional-offers-in-your-app)
- [Identity-bound JWS signing](https://developer.apple.com/documentation/storekit/generating-jws-to-sign-app-store-requests)
- [Legacy signature lifetime and nonce](https://developer.apple.com/documentation/storekit/generating-a-signature-for-promotional-offers)
- [Subscription price changes](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions)
