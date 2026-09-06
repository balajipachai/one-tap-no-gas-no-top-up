# Web

Next.js App Router, `@privy-io/react-auth` + its `smart-wallets` module, viem, Base Sepolia.

## Setup

1. `npm install`
2. Create a Privy app at [dashboard.privy.io](https://dashboard.privy.io) and enable **Smart
   Wallets** for it — see "Privy dashboard configuration" below. This is required; the app
   won't authenticate without it.
3. Deploy the contracts (see `../contracts/README.md`) and note the two addresses it prints.
4. `cp .env.example .env.local` and fill in all four values:
   - `NEXT_PUBLIC_PRIVY_APP_ID` — from the Privy dashboard.
   - `NEXT_PUBLIC_CHECKOUT_ADDRESS` / `NEXT_PUBLIC_TOKEN_ADDRESS` — from the deploy step.
   - `NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL` — a public Base Sepolia RPC endpoint is fine (this is
     only used for reads: balances, catalog price, order status).
5. `npm run dev`

All four `NEXT_PUBLIC_*` values are client-visible by design (an app id, two contract
addresses, and a read RPC URL) — none of them are secrets. The bundler/paymaster URLs that
*would* be sensitive never appear in this app's code at all; see the sponsorship section below.

## Privy dashboard configuration

1. **Smart Wallets** (dashboard → your app → Smart Wallets): turn it on and pick an account
   implementation (Kernel, Safe, etc. — any of them satisfy this app; it only depends on the
   standard smart-wallet client interface, not on implementation-specific behavior).
2. Under that same page, add **Base Sepolia** as a configured chain and set:
   - **Bundler URL** — defaults to Pimlico's public endpoint if left blank. Fine for a demo;
     set your own for anything beyond that.
   - **Paymaster URL** — this is what makes sponsorship actually happen. Leave it unset and
     buyers will be asked to fund the smart account with Base Sepolia ETH instead.
3. **Embedded Wallets** (dashboard → your app → Embedded Wallets): the app requests
   `createOnLogin: "users-without-wallets"` (see `app/providers.tsx`), so a signer wallet is
   created automatically on first login — that signer is what controls the smart account, it
   is never shown to or used directly by the buyer.

There is no bundler/paymaster config in this app's code — `<SmartWalletsProvider>` just needs
to be present in the tree (see `app/providers.tsx`); it reads whatever was configured on the
dashboard for the active chain. This is deliberate: it keeps every keyed URL out of the
frontend entirely, in the dashboard instead of an env var or a request header this app could
leak.

## How the checkout works

`components/Shop.tsx` is the whole flow:

1. **Read, don't hardcode.** The price comes from `Checkout.catalog(itemId)` on-chain, in the
   token's own base units — never converted through a float. Decimals are read from the
   token's own `decimals()` for display only (`lib/format.ts`), via viem's `formatUnits`.
2. **One tap.** Buying sends `approve(checkout, price)` and `purchase(orderId, itemId)` as a
   single `smartWalletClient.sendTransaction({ calls: [...] })` — one UserOperation, one
   signature prompt, no separate approve step the buyer has to act on.
3. **Order identity, not a UI flag.** `lib/order.ts` generates a random order id up front and
   persists it (with its status) in `localStorage` before any send goes out. A second tap
   while that order is `pending` is a no-op client-side; the actual backstop is
   `Checkout.purchase`'s on-chain revert on a reused `orderId` (see `contracts/README.md`) —
   the client-side guard only prevents a redundant signature prompt, it isn't what makes
   double-charging impossible.
4. **Accepted isn't succeeded.** `sendTransaction` resolving to a hash only means the
   UserOperation was accepted by the bundler. The UI doesn't call that success — it waits for
   `publicClient.waitForTransactionReceipt`, then independently reads
   `Checkout.isOrderFilled(orderId)` back from the contract. Only when both agree does the
   order flip to `success`. A rejected signature, a reverted receipt, or a receipt that
   succeeded but the read-back says the order isn't filled all land on `failed` with a message
   and a retry — never a silently-stuck spinner.
5. **Retry reuses the id.** If a previous attempt's outcome was ambiguous (bundler error,
   dropped connection, tab closed mid-flight), retrying checks `isOrderFilled` *before*
   resending. If it turns out the earlier attempt actually landed, the UI reconciles to
   `success` without submitting anything new.

## Files

- `app/providers.tsx` — `PrivyProvider` + `SmartWalletsProvider`.
- `components/Shop.tsx` — auth gate, balances, faucet, buy flow, order-status panel.
- `lib/config.ts` — chain, contract addresses, the item id (must match what the contract
  owner listed — see `contracts/README.md`).
- `lib/abi.ts` — hand-trimmed ABI fragments for exactly the functions this app calls/reads.
- `lib/order.ts` — order id generation and its `localStorage` record.
- `lib/chain.ts` — a plain read-only viem `publicClient` (separate from the smart-account
  client Privy provides for sending).
- `lib/format.ts` — the only place a token amount is converted for display.

## Verifying this without a real Privy app id

`npm run build` and `npm run lint` both pass with zero network access. Anything past that —
actually logging in, seeing a smart account get created, sending a sponsored transaction —
needs a real Privy app id wired to a real Smart Wallets configuration, which only exists once
you've done the dashboard setup above. `app/page.tsx` is marked `export const dynamic =
"force-dynamic"` so a placeholder/missing app id doesn't fail a production build by trying to
prerender the auth gate — see the comment there.
