// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TestUSD} from "../src/TestUSD.sol";
import {Checkout} from "../src/Checkout.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Deploys TestUSD + Checkout to Base Sepolia and lists the demo item.
///
/// No private key ever touches this script, an env var, or a file: the signer comes from
/// Foundry's encrypted keystore via the CLI `--account`/`--sender` flags, and
/// `vm.startBroadcast()` below is called with no argument so it picks up that CLI-supplied
/// signer. Set up the keystore once with:
///   cast wallet import deployer --interactive
///
/// Optional env vars (see contracts/README.md):
///   OWNER_ADDRESS    - defaults to the deployer (--sender). Owns both contracts after deploy.
///   PAYOUT_ADDRESS   - defaults to OWNER_ADDRESS. Where sale proceeds land.
///   ITEM_PRICE_USD6  - defaults to 40_000000 (i.e. $40.00 at 6 decimals).
///
/// Run with:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url base_sepolia --account deployer --sender <deployer address> \
///     --broadcast --verify
contract Deploy is Script {
    bytes32 public constant CUSHION_COVER_ITEM_ID = keccak256("cushion-cover-standard");
    uint256 public constant DEFAULT_PRICE_USD6 = 40_000_000; // $40.00 at 6 decimals

    function run() external {
        address deployer = msg.sender;

        address owner = vm.envOr("OWNER_ADDRESS", deployer);
        address payoutAddress = vm.envOr("PAYOUT_ADDRESS", owner);
        uint256 price = vm.envOr("ITEM_PRICE_USD6", DEFAULT_PRICE_USD6);

        vm.startBroadcast();

        TestUSD token = new TestUSD(owner);
        Checkout checkout = new Checkout(owner, IERC20(address(token)), payoutAddress);

        if (owner == deployer) {
            checkout.setItem(CUSHION_COVER_ITEM_ID, price, true);
        }

        vm.stopBroadcast();

        console.log("TestUSD deployed at:", address(token));
        console.log("Checkout deployed at:", address(checkout));
        console.log("Owner:", owner);
        console.log("Payout address:", payoutAddress);
        console.log("Item id (cushion-cover-standard):");
        console.logBytes32(CUSHION_COVER_ITEM_ID);
        if (owner != deployer) {
            console.log("NOTE: owner != deployer, so setItem was NOT called - run it separately as owner.");
        }
    }
}
