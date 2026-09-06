# One Tap, No Gas, No Top-Up

A checkout a signed-in buyer completes in one tap, no matter what's in their wallet — because
there's nothing native in it to begin with. Built for Farida, who sells hand-printed cushion
covers and doesn't want her buyers' first stop to be a crypto exchange.

## The setup

| | |
|---|---|
| **Testnet** | Base Sepolia (chain id `84532`) |
| **Payment token** | `TestUSD` (`tUSDC`) — a mock stablecoin deployed for this demo, 6 decimals like real USDC. Anyone can self-serve 100 tUSDC per address per 24h from its `faucet()`. |
| **Account implementation** | Whatever ERC-4337 smart-account implementation is selected in the Privy dashboard's Smart Wallets settings (Kernel, Safe, etc. — the app only depends on Privy's smart-wallet client interface, not on a specific implementation). |
| **Gas sponsorship** | Configured entirely in the Privy dashboard (a paymaster URL against the Base Sepolia chain config), not in application code. See `web/README.md`. |
| **Price** | $40.00 flat, for one catalog item ("cushion cover, standard"), read from the contract — never hardcoded client-side. |

## Layout

- **`contracts/`** — `TestUSD` (the test ERC-20) and `Checkout` (the storefront), Foundry,
  17 passing tests, Slither-clean. Deploy instructions and the order-identity state machine
  are in `contracts/README.md`.
- **`web/`** — the Next.js app. Setup (including the Privy dashboard steps that actually turn
  on smart wallets and sponsorship) and how the checkout flow works are in `web/README.md`.
- **`LEARNINGS.md`** — what this build was actually for: how batching, sponsorship, and order
  state fit together, plus the Privy smart-wallets integration gotchas hit along the way.

## Quickstart

```shell
# 1. contracts
cd contracts
forge test
# deploy (see contracts/README.md for the keystore-based, no-key-in-a-file flow)

# 2. web
cd ../web
npm install
cp .env.example .env.local   # fill in: Privy app id, the two deployed addresses, an RPC url
npm run dev
```

## Acceptance criteria, and where each one lives

A buyer with zero native balance taps once, approves nothing else, and lands on an order state
that reflects what actually happened on chain:

- **Zero native balance, one tap**: the smart account never holds or needs Base Sepolia ETH
  (sponsorship), and `approve` + `purchase` go out as one `sendTransaction({ calls: [...] })`
  — one signature, one UserOperation. `web/components/Shop.tsx`.
- **Right about when the order exists**: `Checkout.purchase` reverts on a reused `orderId`
  regardless of caller or item (`contracts/src/Checkout.sol`); the client persists the order id
  and its status before sending, so a reload or a second tap can't fork into two attempts
  (`web/lib/order.ts`). The UI only calls an order `success` after reading the transaction
  receipt *and* `isOrderFilled` back from the contract — never on the send promise resolving,
  never optimistically.
- **Shop vocabulary**: the order panel shows what was bought, what it cost, and one of
  *processing / confirmed / failed* — not a hash or a raw contract error.
- **No secrets committed**: no private key, bundler URL, or paymaster URL appears anywhere in
  this repo. See "No secrets" below.

## No secrets

- Contracts are deployed with `cast wallet import` + `forge script --account` — a private key
  never touches a file, an env var, or this repo. See `contracts/README.md`.
- The frontend's env vars (`web/.env.example`) are a Privy app id, two contract addresses, and
  a public read RPC URL — none of them are secrets, and none of the bundler/paymaster URLs
  that *would* be sensitive ever appear in application code; they live only in the Privy
  dashboard. See `web/README.md`.
- Both `.gitignore`s exclude local env files (`.env*`, with `.env.example` explicitly kept) and
  build/cache artifacts.
