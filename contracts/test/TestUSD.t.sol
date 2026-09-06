// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TestUSD} from "../src/TestUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestUSDTest is Test {
    TestUSD internal token;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        token = new TestUSD(owner);
    }

    function test_decimalsIsSix() public view {
        assertEq(token.decimals(), 6);
    }

    function test_ownerCanMint() public {
        vm.prank(owner);
        token.mint(alice, 1_000e6);
        assertEq(token.balanceOf(alice), 1_000e6);
    }

    function test_nonOwnerCannotMint() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.mint(alice, 1);
    }

    function test_faucetMintsFixedAmount() public {
        vm.prank(alice);
        token.faucet();
        assertEq(token.balanceOf(alice), token.FAUCET_AMOUNT());
    }

    function test_faucetRevertsDuringCooldown() public {
        vm.startPrank(alice);
        token.faucet();
        vm.expectRevert(
            abi.encodeWithSelector(TestUSD.FaucetOnCooldown.selector, block.timestamp + token.FAUCET_COOLDOWN())
        );
        token.faucet();
        vm.stopPrank();
    }

    function test_faucetWorksAgainAfterCooldown() public {
        vm.startPrank(alice);
        token.faucet();
        vm.warp(block.timestamp + token.FAUCET_COOLDOWN());
        token.faucet();
        vm.stopPrank();
        assertEq(token.balanceOf(alice), token.FAUCET_AMOUNT() * 2);
    }
}
