import { Shop } from "@/components/Shop";

// The whole page is behind Privy auth and reads live chain state — nothing here is
// meaningfully static, and prerendering it would run PrivyProvider's app-id check at
// build time (failing the build unless a real app id happens to be set then).
export const dynamic = "force-dynamic";

export default function Home() {
  return (
    <main>
      <header className="site">
        <div>
          <h1>Farida&rsquo;s Workshop</h1>
          <p>One tap, no gas, no top-up.</p>
        </div>
      </header>
      <Shop />
      <footer className="hint">
        Base Sepolia testnet · paid in tUSDC, a mock stablecoin deployed for this demo. Gas is
        sponsored — this wallet never needs ETH.
      </footer>
    </main>
  );
}
