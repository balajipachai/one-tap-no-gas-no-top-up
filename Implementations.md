# Problem Statement:

One Tap, No Gas, No Top-Up
Farida sells hand-printed cushion covers to customers in about a dozen countries. Card processing takes roughly 4% of every order, so she wants to accept a stablecoin instead. The money is not the hard part. Checkout is.

Her last build asked a buyer to approve the token, then pay, and to hold the network's native currency in order to do either. Three confirmations and a top-up before anyone could buy a forty-dollar cushion cover. Of the people who reached that screen, none finished. One emailed her to ask which exchange to open an account with.

# Tech Stack

- Next.js
- @privy-io/react-auth
- @privy-io/react-auth/smart-wallets
- viem
- Base Sepolia
- A test ERC-20

# Learnings

1. How a smart account turns several contract calls into one thing a user approves once
2. What gas sponsorship removes from a checkout, and what it does not
3. Why the moment a purchase becomes real is a design decision, not just a promise resolving
4. The difference between a transaction that was accepted and one that succeeded

# What to do:

1. A checkout a signed-in buyer completes in a single tap. Whatever the contract needs, the buyer approves it once.
2. No native balance anywhere in the flow. A buyer with an empty wallet must be able to complete a purchase.
3. Be right about when the order exists. A double tap must not buy twice, a pending operation must not be shown as complete, and a rejected or failed send must land the buyer somewhere real.
4. Show the buyer an order, in the vocabulary of a shop. What they bought, what it cost, what state it is in.
5. Pick a testnet, a test token, and a sane price. Put the choices in the README.

# Output

- Deliverable. One public GitHub repo containing the app and any contract you wrote. A README naming the testnet, the token, the account implementation, and how sponsorship is configured. No secrets committed.
- Create an overall learnings document at the end and also add about privy's smart wallet details and its gotchas

# Acceptance Criteria:

A buyer with zero native balance taps once, approves nothing else, and lands on an order state that reflects what actually happened on chain.

# Test Cases:

1. The app is wrapped in Privy's smart wallets provider - 4 points
Passes if A smart-account provider or client is set up in the app's provider tree or a module the app imports.
Fails if No smart-account provider or client construction appears anywhere in the repo, and the only wallet surface is the embedded wallet.

2. The purchase is sent through the smart-wallet client - 16 points
Passes if The purchase send is issued on the smart-account client.
Fails if The purchase send is issued on the embedded wallet or its provider (for example useWallets() plus getEthereumProvider, sendTransaction on an EOA wallet object), or no send is issued anywhere.

3. Approve and transfer are submitted as one send - 16 points
Passes if The approve and the payment reach the network through one send invocation carrying multiple calls, or the design provably needs only one call and the code shows why.
Fails if The path issues two or more sequential sends for a single purchase, or there is no purchase path in the repo at all.

4. The address shown to the buyer is the smart account's - 8 points
Passes if Every address surfaced to the buyer resolves to the smart account.
Fails if An address surfaced to the buyer resolves to the embedded signer EOA, or the app renders no address anywhere despite the purchase flow depending on one.

5. Token amounts are computed with a decimals-aware helper - 8 points
Passes if Every amount passed into a call is produced by a decimals-aware conversion or is already an integer base-unit constant.
Fails if Any amount reaches a call through float arithmetic, string concatenation of zeros, or a hardcoded number whose decimals are unexplained, or no amount is passed because the payment is stubbed.

6. The success state waits on the send's resolved result - 7 points
Passes if The success state is set only after the send resolves, or after a receipt or status is read.
Fails if The success state is set immediately on click, on a timer, in a fire-and-forget branch, or optimistically with no later reconciliation, or no success state exists.

7. Repeat submissions are guarded by order identity - 6 points
Passes if A second invocation for the same order is rejected or deduplicated by something keyed to that order's identity.
Fails if The only protection is a UI disabled state or an in-memory boolean, or there is no duplicate protection anywhere on the purchase path.

8. A failed send has a defined outcome in the UI - 7 points
Passes if A rejected or failed send leads to state that renders something the buyer can see and act on.
Fails if The send has no rejection handling, or the rejection path only logs to the console and leaves the UI in its pending state.

9. No credential appears in any tracked file - 8 points
Passes if No secret value appears in any tracked file; keyed URLs and secrets are read from environment variables and any local env file is gitignored.
Fails if Any keyed bundler or paymaster URL, provider key, app secret, or private key is present in a tracked file, including commented out or in an example file with a real value.

# Important

- For smart contracts refer /Users/iamthebatman/Desktop/github.com/balajipachai/solidity-dev-skill
- Privy Docs: https://docs.privy.io/

