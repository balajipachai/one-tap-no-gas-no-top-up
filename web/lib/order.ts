import { keccak256, toBytes, type Hex } from "viem";

export type OrderStatus = "idle" | "pending" | "success" | "failed";

export interface OrderRecord {
  id: Hex;
  itemId: Hex;
  status: OrderStatus;
  txHash?: Hex;
  error?: string;
  createdAt: number;
  updatedAt: number;
}

const STORAGE_KEY = "one-tap-checkout:order:v1";

/** A fresh, unpredictable order id. Persisted before any send goes out so that a page
 * reload, a second tab, or a retry all refer to the same on-chain order identity instead
 * of minting a new one — the contract's `orders[orderId]` guard is only as good as the
 * client consistently reusing this id for one purchase attempt. */
export function newOrderId(): Hex {
  return keccak256(toBytes(crypto.randomUUID()));
}

export function loadOrder(): OrderRecord | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as OrderRecord;
  } catch {
    return null;
  }
}

export function saveOrder(record: OrderRecord): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(record));
}

export function clearOrder(): void {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(STORAGE_KEY);
}

/** Returns the order to act on for this itemId: the persisted one if it's still relevant
 * (anything other than a finished 'success'), or a brand-new 'idle' one otherwise. This is
 * the client-side half of duplicate-submission protection — it's keyed to the order's own
 * id in durable storage, not an in-memory flag, so it survives reloads. The on-chain
 * `orders[orderId]` revert in Checkout.purchase is the half that actually can't be bypassed. */
export function getOrCreateOrder(itemId: Hex): OrderRecord {
  const existing = loadOrder();
  if (existing && existing.itemId === itemId && existing.status !== "success") {
    return existing;
  }
  const now = Date.now();
  const fresh: OrderRecord = {
    id: newOrderId(),
    itemId,
    status: "idle",
    createdAt: now,
    updatedAt: now,
  };
  saveOrder(fresh);
  return fresh;
}
