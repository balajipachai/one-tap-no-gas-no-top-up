# Learnings

## 1. A smart account turns several contract calls into one thing a user approves once

The old flow was three separate things a buyer had to get through: approve, then pay, and — to
do either — hold the chain's native currency to pay for gas. Each of those is a place someone
leaves.

An ERC-4337 smart account collapses the first two into one. `Checkout` still needs two
distinct calls under the hood — `approve` on the token, `purchase` on the checkout contract —
because that's how ERC-20's pull-payment model works; nothing about a smart account changes
that. What changes is *who bundles them*. A regular EOA can only ever sign and send one
transaction at a time, so those two calls have to be two sequential round trips, two prompts,
two chances to bail. A smart account has an `execute`/`executeBatch` entry point built into the
account contract itself — from the outside, `smartWalletClient.sendTransaction({ calls: [...]
} )` looks like one function call, but what actually reaches the chain is one UserOperation
whose calldata tells the smart account "run these two calls, in this order, in the same
transaction." One signature from the buyer authorizes both. If either call reverts, the whole
UserOperation reverts — there's no partial state where the approve went through but the
purchase didn't.

The practical upshot: batching isn't a UX nicety layered on top of the same on-chain shape as
before. It changes what "one tap" can honestly mean. Without it, "one tap" would require either
a pre-existing infinite approval (a real security tradeoff, and still two transactions the
first time) or lying about what the button does.

## 2. What gas sponsorship removes from a checkout, and what it does not

It removes exactly one thing: the buyer needs a balance of the chain's native currency (Base
Sepolia ETH here) to pay for their transaction's gas. That's the "no top-up" in the brief, and
it's real — this app's smart account never holds, checks, or references Base Sepolia ETH
anywhere.

It does not remove gas *costs* — someone still pays for the compute. Here that's the app
(via whatever paymaster is configured in the Privy dashboard); in production it'd be a real
cost with a real budget. It does not remove the *need for a signature* — the buyer still
authorizes the UserOperation with their embedded wallet's key; sponsorship pays the gas bill,
it doesn't impersonate the buyer. And it does not change anything about the payment token
itself — sponsorship covers gas, not the $40 of tUSDC the buyer is actually paying, which still
has to come from their own balance (hence the faucet).

It's tempting to describe sponsorship as "gasless," and the UI copy in this app leans on that
word too. The more accurate frame is: gas became someone else's problem, on a different asset,
paid through a different channel (the paymaster) than the one carrying the actual sale.

## 3. Why the moment a purchase becomes real is a design decision, not just a promise resolving

There's an actual event that makes a purchase real: the block where `Checkout.purchase`'s
`transferFrom` lands and `orders[orderId]` gets set. Everything else — a signature being
collected, a UserOperation being submitted, a bundler accepting it, `sendTransaction`'s promise
resolving — is *evidence* that this event probably happened, with decreasing degrees of
certainty the earlier you look.

The lazy version of a checkout UI treats "the button's onClick handler ran without throwing" as
the moment of truth and flips to a success screen immediately. That's wrong in an ordinary way
even for a plain L1 transaction (the transaction could still revert), and wrong in a specific,
extra way for account abstraction: the promise from `sendTransaction` can resolve once a
bundler *accepts* the UserOperation, which is a weaker claim than the inner calls having
executed successfully (see the next section). Treating either of those as "done" means telling
a buyer they own something they may not, and there's no natural moment afterward where the UI
would ever go back and correct that.

This app puts the moment of truth explicitly where the contract puts it: after the
transaction receipt comes back *and* an independent read of `Checkout.isOrderFilled(orderId)`
agrees. That's a deliberate choice about which layer gets to declare success — not a default
that falls out of "the async function returned."

## 4. The difference between a transaction that was accepted and one that succeeded

In account abstraction terms: a bundler including a UserOperation in a bundle it submits
on-chain (giving you a transaction hash) is not the same claim as the UserOperation's inner
calls having executed without reverting. A smart account's `execute`/`executeBatch` can itself
revert — insufficient allowance, a paused contract, the order-id guard in this app's own
`Checkout` — and depending on the account implementation, that can surface as a *successful*
outer transaction (the UserOperation "landed," EntryPoint collected its gas) wrapping a
*failed* inner call. "Accepted" describes the outer transaction; "succeeded" describes what the
buyer actually cares about, which is one layer deeper.

This app checks both layers instead of trusting the first one: `waitForTransactionReceipt` for
the outer transaction status, then `isOrderFilled` read directly off `Checkout` for the inner
outcome. Only agreement between the two flips an order to `success`; anything else — a receipt
that reverted, or a receipt that "succeeded" while the order still isn't recorded — is treated
as a failure with a retry path, not a false positive.

---

## Privy smart wallets: details and gotchas hit while building this

- **The provider nesting is specific.** `SmartWalletsProvider` (from
  `@privy-io/react-auth/smart-wallets`) goes *inside* `PrivyProvider`, not beside it, and
  `useSmartWallets()` only returns a `client` once a user is authenticated and their smart
  account has been provisioned — code that calls it needs to handle `client` being `undefined`
  during that window, not assume it's there because the provider is mounted.

- **Two peer packages aren't auto-installed.** `@privy-io/react-auth`'s `smart-wallets`
  subpath imports from `permissionless` and `ox` at module scope, but neither is a hard
  `dependency` of the package — they're expected to already be in the app's own
  `node_modules`. `npm install @privy-io/react-auth` alone installs cleanly and `npm run dev`
  even boots fine; the failure only shows up as a webpack/Turbopack `Module not found` at
  **build** time, the first time something actually imports the `smart-wallets` subpath. Worse,
  the versions have to line up exactly: `permissionless` pins `ox` via `peerOptional
  ox: "^0.8.0"`, so installing the latest `ox` (1.x at the time of this build) breaks
  `npm install` itself with an ERESOLVE conflict. Check `permissionless`'s own
  `peerDependencies` for the `ox` range it actually wants before picking a version.

- **The app id check has two layers, and they fail differently.** `PrivyProvider` first checks
  the app id is a 25-character string, synchronously, before anything else runs. If that
  passes, it then makes a real network call to Privy's API to fetch the app's config — and
  *that* call is what actually fails for a made-up (but correctly-shaped) id, surfacing as a
  console warning (`PrivyApiError: Invalid Privy app ID`) rather than a thrown exception, with
  `ready` simply never becoming `true`. Practically: you cannot get further than "stuck on a
  loading state" without a real, dashboard-registered app id — there's no way to fake enough of
  Privy's initialization to exercise the authenticated UI without one.

- **That network call runs during SSR too, which can fail a production build.** Because
  `PrivyProvider` sits in the root layout, Next.js's static prerendering pass executes it
  server-side for any statically-rendered route — including the automatic `/_not-found` page,
  which exists whether or not you reference it. Prerendering throws the same "invalid app id"
  error at *build* time if the id isn't a real, live one at that moment. The fix used here:
  mark the auth-gated page `export const dynamic = "force-dynamic"` so it renders per-request
  instead of being prerendered, which is honest anyway — a page whose entire content depends
  on live auth state and live chain reads was never a candidate for static generation.

- **`embeddedWallets` config is nested, and older examples show it flat.** Current config
  shape is `embeddedWallets: { ethereum: { createOnLogin: '...' } }`. A number of starter
  repos and older blog posts show `embeddedWallets: { createOnLogin: '...' }` at the top level
  — that's a real API shape from an earlier major version, not a typo, so cross-checking against
  whatever `@privy-io/react-auth` version is actually installed (not the version a tutorial was
  written against) matters more than usual here.

- **The smart account's address doesn't come from `useWallets()`.** It's on the user object:
  `user.linkedAccounts.find(account => account.type === 'smart_wallet')`. `useWallets()` /
  `getEthereumProvider()` reach the *embedded* wallet (the signer), which is a real address on
  Base Sepolia but is not the account that should ever be shown to or funded by a buyer — code
  that surfaces an address to the user from the wallet hooks instead of `linkedAccounts` is
  showing the wrong account.

- **Sponsorship is a dashboard setting, not a prop.** There's no bundler/paymaster URL, API
  key, or sponsorship policy in this app's code anywhere — `<SmartWalletsProvider>` just needs
  to exist in the tree. What it actually sponsors is entirely a function of what's configured
  against the active chain in the Privy dashboard's Smart Wallets settings. This is good for
  key hygiene (nothing sensitive to ever leak from the frontend) but means "why isn't gas being
  sponsored" is never a code question first — it's a dashboard-configuration question.
