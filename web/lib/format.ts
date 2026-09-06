import { formatUnits } from "viem";

/** Decimals-aware base-units -> display string. Never do float math on the raw amount;
 * this is the only place a token amount is converted for a human to read. */
export function formatTokenAmount(amount: bigint, decimals: number): string {
  const asString = formatUnits(amount, decimals);
  return Number(asString).toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function shortenHash(hash: string): string {
  return `${hash.slice(0, 10)}...${hash.slice(-6)}`;
}
