// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDUSD} from "../src/IMDUSD.sol";

/// @dev Drives random action sequences and maintains an independent ledger of expected outcomes.
contract TokenHandler is Test {
    IMDUSD private immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401), address(0xDA401)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(IMDUSD token_) {
        token = token_;
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        amount = bound(amount, 0, approved < available ? approved : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    function transferFromAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        if (approved == type(uint256).max) return;
        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, approved + 1)));
        assertFalse(success, "an allowance must bound delegated spending");
        assertEq(
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
    }

    /// @dev Make revocation and the infinite-allowance boundary frequent in random sequences.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 choice) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory amounts = [uint256(0), 1, 1_000_000_000 ether, type(uint256).max - 1, type(uint256).max];
        uint256 amount = amounts[choice % amounts.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        amount = bound(amount, held + 1, type(uint256).max);
        vm.prank(from);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertFalse(success, "insufficient funds must not create tokens, even for self-transfers");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        // No ghost update: the global invariant checks every balance and allowance for rollback.
    }

    function transferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[owner];
        amount = bound(amount, held + 1, type(uint256).max);
        uint256 approval = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approval));
        expectedAllowance[owner][spender] = approval;

        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertFalse(success, "approval cannot substitute for a balance");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (address(0), amount)));
        assertFalse(success, "transferring to zero must not burn supply");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 held = expectedBalance[owner];
        amount = bound(amount, 0, approved < held ? approved : held);
        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, address(0), amount)));
        assertFalse(success, "invalid recipient must revert without spending allowance");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.prank(owner);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        assertFalse(success, "zero address must never receive spending authority");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
    }

    /// @dev After any history a holder can move its entire balance and receive it back without a fee.
    function fullBalanceRoundTrip(uint256 fromSeed, uint256 toSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
        // The round trip is an identity, including all pre-existing approvals.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IMDUSDInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDUSD private token;
    TokenHandler private handler;

    function setUp() public {
        token = new IMDUSD();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.transferFromAboveAllowance.selector;
        selectors[4] = TokenHandler.approveBoundary.selector;
        selectors[5] = TokenHandler.transferAboveBalance.selector;
        selectors[6] = TokenHandler.transferFromAboveBalance.selector;
        selectors[7] = TokenHandler.transferToZero.selector;
        selectors[8] = TokenHandler.transferFromToZero.selector;
        selectors[9] = TokenHandler.approveZeroSpender.selector;
        selectors[10] = TokenHandler.fullBalanceRoundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyAndExactBalancesAndAllowances() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.name(), "imdUsd");
        assertEq(token.symbol(), "IMDUSD");
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            uint256 held = token.balanceOf(owner);
            balances += held;
            assertEq(held, handler.expectedBalance(owner));
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(balances, SUPPLY, "tokens must be conserved across every action sequence");
    }
}
