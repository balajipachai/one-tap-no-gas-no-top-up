// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Checkout} from "../src/Checkout.sol";
import {TestUSD} from "../src/TestUSD.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CheckoutTest is Test {
    Checkout internal checkout;
    TestUSD internal token;

    address internal owner = makeAddr("owner");
    address internal seller = makeAddr("seller");
    address internal buyer = makeAddr("buyer");

    bytes32 internal constant ITEM_ID = keccak256("cushion-cover-standard");
    uint256 internal constant PRICE = 40e6; // $40.00 at 6 decimals

    function setUp() public {
        token = new TestUSD(owner);
        checkout = new Checkout(owner, IERC20(address(token)), seller);

        vm.prank(owner);
        checkout.setItem(ITEM_ID, PRICE, true);

        vm.prank(owner);
        token.mint(buyer, 1_000e6);
    }

    function _approveAndPurchase(bytes32 orderId) internal {
        vm.startPrank(buyer);
        token.approve(address(checkout), PRICE);
        checkout.purchase(orderId, ITEM_ID);
        vm.stopPrank();
    }

    function test_purchase_pullsPaymentAndRecordsOrder() public {
        bytes32 orderId = keccak256("order-1");
        _approveAndPurchase(orderId);

        assertEq(token.balanceOf(seller), PRICE);
        assertEq(token.balanceOf(buyer), 1_000e6 - PRICE);

        Checkout.Order memory order = checkout.getOrder(orderId);
        assertEq(order.buyer, buyer);
        assertEq(order.itemId, ITEM_ID);
        assertEq(order.amount, PRICE);
        assertGt(order.filledAt, 0);
        assertTrue(checkout.isOrderFilled(orderId));
    }

    function test_purchase_emitsOrderPurchased() public {
        bytes32 orderId = keccak256("order-2");
        vm.startPrank(buyer);
        token.approve(address(checkout), PRICE);

        vm.expectEmit(true, true, true, true);
        emit Checkout.OrderPurchased(orderId, buyer, ITEM_ID, PRICE, uint64(block.timestamp));
        checkout.purchase(orderId, ITEM_ID);
        vm.stopPrank();
    }

    function test_purchase_revertsOnDuplicateOrderId() public {
        bytes32 orderId = keccak256("order-3");
        _approveAndPurchase(orderId);

        // Buyer (or an attacker replaying the same UserOperation) tries again.
        vm.startPrank(buyer);
        token.approve(address(checkout), PRICE);
        vm.expectRevert(abi.encodeWithSelector(Checkout.OrderAlreadyExists.selector, orderId));
        checkout.purchase(orderId, ITEM_ID);
        vm.stopPrank();

        // Only charged once.
        assertEq(token.balanceOf(seller), PRICE);
    }

    function test_purchase_duplicateOrderIdRevertsEvenForDifferentItemOrBuyer() public {
        bytes32 orderId = keccak256("order-4");
        _approveAndPurchase(orderId);

        address otherBuyer = makeAddr("otherBuyer");
        vm.prank(owner);
        token.mint(otherBuyer, 1_000e6);

        vm.startPrank(otherBuyer);
        token.approve(address(checkout), PRICE);
        vm.expectRevert(abi.encodeWithSelector(Checkout.OrderAlreadyExists.selector, orderId));
        checkout.purchase(orderId, ITEM_ID);
        vm.stopPrank();
    }

    function test_purchase_revertsWhenItemNotActive() public {
        bytes32 unknownItem = keccak256("does-not-exist");
        vm.startPrank(buyer);
        token.approve(address(checkout), PRICE);
        vm.expectRevert(abi.encodeWithSelector(Checkout.ItemNotActive.selector, unknownItem));
        checkout.purchase(keccak256("order-5"), unknownItem);
        vm.stopPrank();
    }

    function test_purchase_revertsWithoutAllowance() public {
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(checkout), 0, PRICE)
        );
        checkout.purchase(keccak256("order-6"), ITEM_ID);
    }

    function test_purchase_revertsWithInsufficientBalance() public {
        address poorBuyer = makeAddr("poorBuyer");
        vm.startPrank(poorBuyer);
        token.approve(address(checkout), PRICE);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, poorBuyer, 0, PRICE)
        );
        checkout.purchase(keccak256("order-7"), ITEM_ID);
        vm.stopPrank();
    }

    function test_onlyOwnerCanListItems() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        checkout.setItem(ITEM_ID, 1, true);
    }

    function test_onlyOwnerCanUpdatePayoutAddress() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        checkout.setPayoutAddress(buyer);
    }

    function test_constructorRejectsZeroAddresses() public {
        vm.expectRevert(Checkout.ZeroAddress.selector);
        new Checkout(owner, IERC20(address(0)), seller);

        vm.expectRevert(Checkout.ZeroAddress.selector);
        new Checkout(owner, IERC20(address(token)), address(0));
    }

    function testFuzz_purchase_succeedsForAnyDistinctOrderIds(bytes32 orderIdA, bytes32 orderIdB) public {
        vm.assume(orderIdA != orderIdB);

        vm.prank(owner);
        token.mint(buyer, PRICE); // top up so two purchases can clear

        vm.startPrank(buyer);
        token.approve(address(checkout), PRICE * 2);
        checkout.purchase(orderIdA, ITEM_ID);
        checkout.purchase(orderIdB, ITEM_ID);
        vm.stopPrank();

        assertTrue(checkout.isOrderFilled(orderIdA));
        assertTrue(checkout.isOrderFilled(orderIdB));
        assertEq(token.balanceOf(seller), PRICE * 2);
    }
}
