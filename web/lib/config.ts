import { keccak256, toBytes, type Address } from "viem";
import { baseSepolia } from "viem/chains";

function requireEnv(name: string, value: string | undefined): Address {
  if (!value) {
    throw new Error(
      `Missing ${name}. Copy web/.env.example to web/.env.local and fill it in.`,
    );
  }
  return value as Address;
}

/** The one item this shop sells. Must match the id the Checkout owner listed on-chain
 * (see contracts/script/Deploy.s.sol: CUSHION_COVER_ITEM_ID). Derived the same way
 * Solidity's `keccak256("cushion-cover-standard")` hashes a string literal: over its raw
 * UTF-8 bytes, no ABI encoding. */
export const ITEM_ID = keccak256(toBytes("cushion-cover-standard"));

export const ITEM_NAME = "Hand-printed cushion cover";
export const ITEM_DESCRIPTION =
  "Block-printed by hand, one panel at a time. Farida's workshop, made to order.";

export const chain = baseSepolia;

export const rpcUrl =
  process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL ?? "https://sepolia.base.org";

export const checkoutAddress = requireEnv(
  "NEXT_PUBLIC_CHECKOUT_ADDRESS",
  process.env.NEXT_PUBLIC_CHECKOUT_ADDRESS,
);

export const tokenAddress = requireEnv(
  "NEXT_PUBLIC_TOKEN_ADDRESS",
  process.env.NEXT_PUBLIC_TOKEN_ADDRESS,
);

export const privyAppId = requireEnv(
  "NEXT_PUBLIC_PRIVY_APP_ID",
  process.env.NEXT_PUBLIC_PRIVY_APP_ID,
);
