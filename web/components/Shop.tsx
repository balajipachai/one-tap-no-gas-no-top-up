"use client";

import { useCallback, useEffect, useState } from "react";
import { encodeFunctionData, type Hex } from "viem";
import { usePrivy } from "@privy-io/react-auth";
import { useSmartWallets } from "@privy-io/react-auth/smart-wallets";
import { checkoutAddress, tokenAddress, ITEM_ID, ITEM_NAME, ITEM_DESCRIPTION } from "@/lib/config";
import { checkoutAbi, erc20Abi } from "@/lib/abi";
import { publicClient } from "@/lib/chain";
import { formatTokenAmount, shortenAddress, shortenHash } from "@/lib/format";
import { clearOrder, getOrCreateOrder, saveOrder, type OrderRecord } from "@/lib/order";

type LoadState = {
  decimals: number;
  price: bigint;
  itemActive: boolean;
  balance: bigint;
};

export function Shop() {
  const { ready, authenticated, user, login, logout } = usePrivy();
  const { client: smartWalletClient } = useSmartWallets();

  const smartWalletAddress = user?.linkedAccounts.find(
    (account) => account.type === "smart_wallet",
  )?.address as Hex | undefined;

  const [data, setData] = useState<LoadState | null>(null);
  const [order, setOrder] = useState<OrderRecord | null>(() => getOrCreateOrder(ITEM_ID));
  const [buying, setBuying] = useState(false);
  const [claimingFaucet, setClaimingFaucet] = useState(false);
  const [faucetMessage, setFaucetMessage] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!smartWalletAddress) return;
    const [decimals, catalogItem, balance] = await Promise.all([
      publicClient.readContract({
        address: tokenAddress,
        abi: erc20Abi,
        functionName: "decimals",
      }),
      publicClient.readContract({
        address: checkoutAddress,
        abi: checkoutAbi,
        functionName: "catalog",
        args: [ITEM_ID],
      }),
      publicClient.readContract({
        address: tokenAddress,
        abi: erc20Abi,
        functionName: "balanceOf",
        args: [smartWalletAddress],
      }),
    ]);
    setData({ decimals, price: catalogItem[0], itemActive: catalogItem[1], balance });
  }, [smartWalletAddress]);

  useEffect(() => {
    if (smartWalletAddress) {
      // refresh() sets state asynchronously (after its awaits resolve), not synchronously
      // in this effect body, but the linter can't see through that — data fetching in an
      // effect tied to smartWalletAddress is the actual pattern here.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      void refresh();
    }
  }, [smartWalletAddress, refresh]);

  const updateOrder = (patch: Partial<OrderRecord>) => {
    setOrder((prev) => {
      if (!prev) return prev;
      const next: OrderRecord = { ...prev, ...patch, updatedAt: Date.now() };
      saveOrder(next);
      return next;
    });
  };

  const handleFaucet = async () => {
    if (!smartWalletClient || claimingFaucet) return;
    setClaimingFaucet(true);
    setFaucetMessage(null);
    try {
      const txHash = await smartWalletClient.sendTransaction({
        to: tokenAddress,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "faucet" }),
      });
      await publicClient.waitForTransactionReceipt({ hash: txHash });
      await refresh();
      setFaucetMessage("Test funds arrived.");
    } catch (err) {
      setFaucetMessage(err instanceof Error ? err.message : "Faucet claim failed.");
    } finally {
      setClaimingFaucet(false);
    }
  };

  const handleBuy = async () => {
    if (!smartWalletClient || !data || !order) return;
    // Guard against a double tap: a submission already in flight for this exact order
    // id is a no-op, not a resend. This is on top of the on-chain guard in Checkout.purchase.
    if (order.status === "pending") return;

    setBuying(true);
    updateOrder({ status: "pending", error: undefined });

    try {
      // A retry of a failed attempt might have actually landed on-chain (the send was
      // accepted but we never learned the outcome). The contract is the source of truth,
      // so check it before resending with the same order id.
      const alreadyFilled = await publicClient.readContract({
        address: checkoutAddress,
        abi: checkoutAbi,
        functionName: "isOrderFilled",
        args: [order.id],
      });
      if (alreadyFilled) {
        updateOrder({ status: "success" });
        await refresh();
        return;
      }

      const txHash = await smartWalletClient.sendTransaction({
        calls: [
          {
            to: tokenAddress,
            data: encodeFunctionData({
              abi: erc20Abi,
              functionName: "approve",
              args: [checkoutAddress, data.price],
            }),
          },
          {
            to: checkoutAddress,
            data: encodeFunctionData({
              abi: checkoutAbi,
              functionName: "purchase",
              args: [order.id, ITEM_ID],
            }),
          },
        ],
      });

      updateOrder({ txHash });

      // A UserOperation being accepted by the bundler is not the same as the inner calls
      // succeeding. Wait for the receipt, then confirm against the contract itself —
      // that's the actual "did the purchase happen" answer, not the send promise resolving.
      const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
      const filled = await publicClient.readContract({
        address: checkoutAddress,
        abi: checkoutAbi,
        functionName: "isOrderFilled",
        args: [order.id],
      });

      if (receipt.status === "success" && filled) {
        updateOrder({ status: "success", txHash });
      } else {
        updateOrder({
          status: "failed",
          txHash,
          error: "The transaction landed but the purchase did not go through.",
        });
      }
      await refresh();
    } catch (err) {
      updateOrder({
        status: "failed",
        error: err instanceof Error ? err.message : "The purchase was rejected or failed to send.",
      });
    } finally {
      setBuying(false);
    }
  };

  const handleBuyAgain = () => {
    clearOrder();
    setOrder(getOrCreateOrder(ITEM_ID));
  };

  if (!ready) {
    return (
      <div className="card">
        <p>Loading…</p>
      </div>
    );
  }

  if (!authenticated) {
    return (
      <div className="card">
        <div className="item-card">
          <div className="item-swatch" aria-hidden />
          <div className="item-info">
            <h2>{ITEM_NAME}</h2>
            <p>{ITEM_DESCRIPTION}</p>
          </div>
        </div>
        <div className="section">
          <button className="btn btn-primary" onClick={login}>
            Sign in to buy
          </button>
        </div>
      </div>
    );
  }

  const price = data?.price ?? 0n;
  const decimals = data?.decimals ?? 6;
  const balance = data?.balance ?? 0n;
  const canAfford = balance >= price;
  const itemActive = data?.itemActive ?? true;

  return (
    <div>
      <div className="card">
        <div className="item-card">
          <div className="item-swatch" aria-hidden />
          <div className="item-info">
            <h2>{ITEM_NAME}</h2>
            <p>{ITEM_DESCRIPTION}</p>
            <div className="price">
              {data ? formatTokenAmount(price, decimals) : "—"} <small>tUSDC</small>
            </div>
          </div>
        </div>

        <div className="section row">
          <span>
            Smart account{" "}
            <span className="mono">
              {smartWalletAddress ? shortenAddress(smartWalletAddress) : "…"}
            </span>
          </span>
          <button className="link-btn" onClick={logout}>
            Sign out
          </button>
        </div>

        <div className="faucet-row">
          <span className="row" style={{ fontSize: "0.85rem" }}>
            Balance: {data ? formatTokenAmount(balance, decimals) : "…"} tUSDC
          </span>
          <button className="link-btn" onClick={handleFaucet} disabled={claimingFaucet}>
            {claimingFaucet ? "Requesting…" : "Get test tUSDC"}
          </button>
        </div>
        {faucetMessage && (
          <p style={{ fontSize: "0.8rem", color: "var(--muted)", marginTop: 6 }}>{faucetMessage}</p>
        )}

        <div className="section">
          <button
            className="btn btn-primary"
            onClick={handleBuy}
            disabled={
              !smartWalletClient ||
              !data ||
              !itemActive ||
              !canAfford ||
              buying ||
              order?.status === "pending" ||
              order?.status === "success" ||
              order?.status === "failed"
            }
          >
            {order?.status === "pending" && <span className="spinner" aria-hidden />}
            {buyButtonLabel(order, canAfford, itemActive)}
          </button>
        </div>
      </div>

      {order && order.status !== "idle" && (
        <div className={`order-panel ${order.status}`}>
          <div className="status-line">
            {order.status === "pending" && (
              <>
                <span className="spinner" aria-hidden /> Processing your order
              </>
            )}
            {order.status === "success" && <>Order confirmed</>}
            {order.status === "failed" && <>Order failed</>}
          </div>

          {order.status === "pending" && (
            <p>Waiting for the network to confirm your one-tap payment. This page will update itself.</p>
          )}

          {order.status === "success" && data && (
            <>
              <p>
                {ITEM_NAME} — {formatTokenAmount(price, decimals)} tUSDC
              </p>
              <p className="mono" style={{ fontSize: "0.78rem" }}>
                order {shortenHash(order.id)}
                {order.txHash && (
                  <>
                    {" · "}
                    <a
                      href={`https://sepolia.basescan.org/tx/${order.txHash}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {shortenHash(order.txHash)}
                    </a>
                  </>
                )}
              </p>
              <div className="section">
                <button className="btn btn-secondary" onClick={handleBuyAgain}>
                  Buy another
                </button>
              </div>
            </>
          )}

          {order.status === "failed" && (
            <>
              <p>{order.error ?? "Something went wrong sending the transaction."}</p>
              <div className="section">
                <button className="btn btn-primary" onClick={handleBuy} disabled={buying}>
                  Try again
                </button>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}

function buyButtonLabel(order: OrderRecord | null, canAfford: boolean, itemActive: boolean): string {
  if (!itemActive) return "Item unavailable";
  if (order?.status === "pending") return "Processing…";
  if (order?.status === "success") return "Order placed";
  if (order?.status === "failed") return "See order status below";
  if (!canAfford) return "Not enough tUSDC — use the faucet above";
  return "Buy — one tap";
}
