// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Checkout
/// @notice A single-seller storefront. A buyer approves this contract to pull the sale
/// price in `paymentToken`, then calls `purchase`; the two calls are meant to reach the
/// chain as one batched user operation from a smart account, but the contract does not
/// assume that — it only assumes `allowance(buyer, address(this)) >= price` at the time
/// `purchase` runs.
///
/// Order identity lives on-chain: `orders[orderId]` is the source of truth for whether a
/// purchase already happened, so a duplicate submission for the same order reverts here
/// regardless of what the UI does.
contract Checkout is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Item {
        uint256 price; // base units of `paymentToken`
        bool active;
    }

    struct Order {
        address buyer;
        bytes32 itemId;
        uint256 amount;
        uint64 filledAt;
    }

    IERC20 public paymentToken;
    address public payoutAddress;

    mapping(bytes32 => Item) public catalog;
    mapping(bytes32 => Order) public orders;

    event ItemListed(bytes32 indexed itemId, uint256 price, bool active);
    event PayoutAddressUpdated(address indexed payoutAddress);
    event PaymentTokenUpdated(address indexed token);
    event OrderPurchased(
        bytes32 indexed orderId, address indexed buyer, bytes32 indexed itemId, uint256 amount, uint64 timestamp
    );

    error ZeroAddress();
    error ItemNotActive(bytes32 itemId);
    error OrderAlreadyExists(bytes32 orderId);

    constructor(address initialOwner, IERC20 paymentToken_, address payoutAddress_) Ownable(initialOwner) {
        if (address(paymentToken_) == address(0) || payoutAddress_ == address(0)) revert ZeroAddress();
        paymentToken = paymentToken_;
        payoutAddress = payoutAddress_;
    }

    /// @notice List or update a catalog item. `itemId` is a stable identifier the app
    /// derives client-side, e.g. `keccak256("cushion-cover-standard")`.
    function setItem(bytes32 itemId, uint256 price, bool active) external onlyOwner {
        catalog[itemId] = Item({price: price, active: active});
        emit ItemListed(itemId, price, active);
    }

    function setPayoutAddress(address payoutAddress_) external onlyOwner {
        if (payoutAddress_ == address(0)) revert ZeroAddress();
        payoutAddress = payoutAddress_;
        emit PayoutAddressUpdated(payoutAddress_);
    }

    function setPaymentToken(IERC20 token) external onlyOwner {
        if (address(token) == address(0)) revert ZeroAddress();
        paymentToken = token;
        emit PaymentTokenUpdated(address(token));
    }

    /// @notice Pull `catalog[itemId].price` from `msg.sender` to `payoutAddress` and record
    /// the sale under `orderId`. Reverts if `orderId` was already used (regardless of which
    /// item or buyer it was used for) or if the item isn't active. Order state is written
    /// before the external `transferFrom` call (checks-effects-interactions); `nonReentrant`
    /// is the second, independent layer.
    function purchase(bytes32 orderId, bytes32 itemId) external nonReentrant {
        if (orders[orderId].filledAt != 0) revert OrderAlreadyExists(orderId);

        Item memory item = catalog[itemId];
        if (!item.active) revert ItemNotActive(itemId);

        orders[orderId] =
            Order({buyer: msg.sender, itemId: itemId, amount: item.price, filledAt: uint64(block.timestamp)});

        paymentToken.safeTransferFrom(msg.sender, payoutAddress, item.price);

        emit OrderPurchased(orderId, msg.sender, itemId, item.price, uint64(block.timestamp));
    }

    function getOrder(bytes32 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    function isOrderFilled(bytes32 orderId) external view returns (bool) {
        return orders[orderId].filledAt != 0;
    }
}
