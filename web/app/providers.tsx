"use client";

import { PrivyProvider } from "@privy-io/react-auth";
import { SmartWalletsProvider } from "@privy-io/react-auth/smart-wallets";
import { chain, privyAppId } from "@/lib/config";

/**
 * Smart-wallet gotcha: gas sponsorship (the bundler + paymaster) is a Dashboard setting,
 * not a prop here — see README.md "Gas sponsorship" section. SmartWalletsProvider only
 * needs to exist in the tree; it reads the account-abstraction config (implementation,
 * bundler URL, paymaster URL) that was set for `chain` in the Privy Dashboard.
 */
export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <PrivyProvider
      appId={privyAppId}
      config={{
        defaultChain: chain,
        supportedChains: [chain],
        embeddedWallets: {
          ethereum: {
            createOnLogin: "users-without-wallets",
          },
        },
      }}
    >
      <SmartWalletsProvider>{children}</SmartWalletsProvider>
    </PrivyProvider>
  );
}
