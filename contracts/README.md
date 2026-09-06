# Contracts

Two contracts, Foundry, Base Sepolia.

- **`TestUSD`** — a mock stablecoin (`tUSDC`, 6 decimals, like real USDC). `mint` is
  owner-only; `faucet()` is open to anyone and mints a fixed 100 tUSDC per address per
  24 hours, so a buyer with a brand-new smart account can fund itself without asking anyone.
- **`Checkout`** — a single-seller storefront. A buyer approves `Checkout` to pull the sale
  price in `paymentToken`, then calls `purchase`. The app sends both calls as one batched
  UserOperation from a Privy smart account (see `../web/`), but the contract doesn't assume
  that — it only requires `allowance(buyer, address(this)) >= price` at the moment `purchase`
  runs.

## State machine

There is no on-chain "pending" state. `purchase` is a single synchronous call: it either
reverts (nothing happened) or completes fully (the transfer landed and `orders[orderId]` is
now set). "Pending" only exists client-side, for the window between submitting a
UserOperation and knowing whether it landed — see the frontend README for how that's
reconciled against the contract afterward.

Order identity is the thing this contract actually owns:

- `orders[orderId]` starts unset.
- The first successful `purchase(orderId, itemId)` sets it permanently — `buyer`, `itemId`,
  `amount`, `filledAt`. This is a one-way transition; nothing in the contract ever clears or
  overwrites an existing order.
- Any later call with the same `orderId` reverts with `OrderAlreadyExists`, regardless of who
  calls it or which item they pass. A double-tap, a retried UserOperation, or two browser tabs
  racing each other on the same order all hit this same guard.

Order state is written *before* the external `transferFrom` call (checks-effects-interactions),
with `nonReentrant` as the second, independent layer — see `src/Checkout.sol`.

## Catalog

`catalog[itemId] = {price, active}`, owner-configurable via `setItem`. The demo lists one item:
`keccak256("cushion-cover-standard")` at `$40.00` (`40_000_000` base units of a 6-decimal
token). The frontend derives the same item id the same way (`keccak256` over the raw UTF-8
bytes of the string, not ABI-encoded) — see `web/lib/config.ts`.

## Tests

`forge test` — 17 tests, all passing:

- `test/TestUSD.t.sol` — owner-only mint, faucet amount, faucet cooldown (including the
  correct-after-cooldown case).
- `test/Checkout.t.sol` — payment pulled and order recorded, the `OrderPurchased` event,
  **duplicate `orderId` reverts** (including when a *different* buyer or item tries to reuse
  it), missing/insufficient allowance, insufficient balance, inactive item, owner-only catalog
  and payout-address changes, zero-address constructor guards, and a fuzz test that any two
  distinct order ids both succeed independently.

Also verified against real bytecode on a local `anvil` node (not part of `forge test`, just a
one-off sanity check while building this): faucet → approve → purchase → balances move
correctly → `isOrderFilled` flips true → a second `purchase` with the same `orderId` reverts
with `OrderAlreadyExists`.

Slither has been run (`slither .`); the only findings are in unmodified OpenZeppelin library
code (its own `Ownable2Step` zero-check pattern) and generic pragma/solc-version notices from
the library's own version ranges — nothing actionable in `src/`.

```shell
forge test
forge test -vvv          # with traces
slither .
```

## Deploying to Base Sepolia

No private key ever goes into a file, an env var, or this repo. The deployer signs through
Foundry's encrypted keystore:

```shell
# once
cast wallet import deployer --interactive

# set these first (see below) — RPC and (optionally) an Etherscan-style key for verification
export BASE_SEPOLIA_RPC_URL=...        # e.g. a Base Sepolia RPC endpoint
export BASESCAN_API_KEY=...            # optional, only needed for --verify

forge script script/Deploy.s.sol:Deploy \
  --rpc-url base_sepolia --account deployer --sender <deployer address> \
  --broadcast --verify
```

`script/Deploy.s.sol` deploys `TestUSD`, deploys `Checkout` pointed at it, and (when the
deployer is also the intended owner) lists the cushion-cover item at $40.00. Optional env vars:

| Var                | Default                  | Meaning                                   |
| ------------------ | ------------------------- | ------------------------------------------ |
| `OWNER_ADDRESS`     | the deployer               | Owns both contracts after deploy            |
| `PAYOUT_ADDRESS`    | `OWNER_ADDRESS`            | Where sale proceeds land                    |
| `ITEM_PRICE_USD6`   | `40_000_000` ($40.00)       | Price of the cushion-cover item             |

Copy the two deployed addresses it prints into `../web/.env.local` as
`NEXT_PUBLIC_TOKEN_ADDRESS` and `NEXT_PUBLIC_CHECKOUT_ADDRESS`.

`foundry.toml` reads `BASE_SEPOLIA_RPC_URL` and `BASESCAN_API_KEY` from the environment via
`${VAR}` interpolation — the tracked config file itself contains no secret or key.

## Repo hygiene

- `.gitignore` excludes `out/`, `cache/`, and `broadcast/*/31337/` (local anvil smoke-test
  runs — not a real deployment record). A real Base Sepolia broadcast (chain `84532`) is fine
  to keep as a record of what was deployed.
- `lib/` (forge-std, OpenZeppelin Contracts v5.7.0) is committed as plain directories rather
  than git submodules. There's no lockfile pinning the dependency versions otherwise, so
  vendoring them is what makes `forge build`/`forge test` reproduce exactly rather than
  picking up whatever each library's default branch happens to be at clone time.
