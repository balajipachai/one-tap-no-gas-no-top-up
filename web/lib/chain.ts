import { createPublicClient, http } from "viem";
import { chain, rpcUrl } from "./config";

/** Plain read-only RPC client — balances, catalog price, order status, and waiting for a
 * transaction receipt. This is separate from the smart-account client Privy provides for
 * sending; it never signs or sends anything. */
export const publicClient = createPublicClient({
  chain,
  transport: http(rpcUrl),
});
