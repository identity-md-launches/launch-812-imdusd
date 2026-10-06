// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDUSD} from "../src/IMDUSD.sol";

/// @dev Models CREATE2 deployment by a factory without granting the factory token privileges.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (IMDUSD) {
        return new IMDUSD{salt: salt}();
    }

    function send(IMDUSD token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

/// forge-config: default.fuzz.runs = 1000
contract IMDUSDTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    IMDUSD private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new IMDUSD();
    }

    function test_metadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "imdUsd");
        assertEq(token.symbol(), "IMDUSD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        IMDUSD deployed = new IMDUSD();
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_directDeploymentMintsToSenderInsteadOfOrigin() public {
        vm.prank(ALICE, BOB);
        IMDUSD deployed = new IMDUSD();
        assertEq(deployed.balanceOf(ALICE), SUPPLY);
        assertEq(deployed.balanceOf(BOB), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_factoryCreate2DeploymentAndExactLaunchTransfers() public {
        TokenFactory factory = new TokenFactory();
        bytes32 salt = keccak256("imdUsd launch");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(IMDUSD).creationCode))
                    )
                )
            )
        );
        IMDUSD deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);

        address distributor = address(0xD157);
        address poolManager = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        uint256 poolShare = SUPPLY / 5;
        assertTrue(factory.send(deployed, distributor, swarm));
        assertEq(deployed.balanceOf(distributor), swarm);
        vm.prank(distributor);
        assertTrue(deployed.transfer(ALICE, swarm));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(ALICE), swarm);

        assertTrue(factory.send(deployed, poolManager, poolShare));
        assertEq(deployed.balanceOf(poolManager), poolShare);
        assertTrue(factory.send(deployed, BOB, SUPPLY - swarm - poolShare));
        assertEq(deployed.balanceOf(BOB), SUPPLY - swarm - poolShare);
        assertEq(deployed.balanceOf(address(factory)), 0);

        // Exercise the token leg in both directions; this is not a DEX settlement simulation.
        vm.prank(poolManager);
        assertTrue(deployed.transfer(SPENDER, 123 ether));
        assertEq(deployed.balanceOf(SPENDER), 123 ether);
        vm.prank(SPENDER);
        assertTrue(deployed.transfer(poolManager, 123 ether));
        assertEq(deployed.balanceOf(SPENDER), 0);
        assertEq(deployed.balanceOf(poolManager), poolShare);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferEmitsAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 25 ether);
        assertTrue(token.transfer(ALICE, 25 ether));
        assertEq(token.balanceOf(ALICE), 25 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRevertsForInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRevertsForMaximumAmountWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferRevertsForZeroRecipientIncludingZeroValue() public {
        for (uint256 amount; amount <= 1; ++amount) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            token.transfer(address(0), amount);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRevertsForZeroSender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
    }

    function test_approveEmitsThenCanReplaceAndRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 10 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertTrue(token.approve(SPENDER, 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 3 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalDoesNotRequireBalanceOrMoveFunds() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveRevertsForZeroSpenderIncludingRevocation() public {
        for (uint256 amount; amount <= 1; ++amount) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amount);
        }
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_approveRevertsForZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, 1);
    }

    function test_transferFromDeliversExactAmountAndConsumesAllowance() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 6 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 6 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
    }

    function test_transferFromWithInfiniteAllowanceLeavesItUnchanged() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_transferFromSelfPreservesBalanceAndConsumesAllowance() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromWithoutApprovalSucceeds() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromRevertsWithoutAllowanceEvenForTokenHolder() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_deployerCannotSpendHolderBalanceWithoutApproval() public {
        assertTrue(token.transfer(ALICE, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
        assertEq(token.balanceOf(BOB), 10 ether);
    }

    function test_transferFromRevertsAboveAllowanceAndPreservesState() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10 ether, 10 ether + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 10 ether + 1);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10 ether);
        assertEq(token.allowance(ALICE, SPENDER), 10 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromZeroRecipientRollsBackAllowance() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnInitializationOrAdministrativeSelectors() public {
        assertTrue(token.transfer(ALICE, 10 ether));
        string[23] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)",
            "burn(uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, 1);
            (bool deployerSucceeded,) = address(token).call(data);
            assertFalse(deployerSucceeded, signatures[i]);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(data);
            assertFalse(strangerSucceeded, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 10 ether);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
        assertEq(token.balanceOf(BOB), 10 ether);
    }

    function test_nativeCurrencyAndUnknownCallsAreRejected() public {
        vm.deal(address(this), 1 ether);
        (bool acceptsNative,) = address(token).call{value: 1 ether}("");
        assertFalse(acceptsNative);
        (bool acceptsUnknown,) = address(token).call(hex"deadbeef");
        assertFalse(acceptsUnknown);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_transferConservesSupplyAndDeliversExactAmount(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConsumesOnlyApprovedAmount(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY);
        amount = bound(amount, 0, approval);
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approval - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_oneWeiCanBeTransferredAndSpentExactly() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumMinusOneAllowanceIsFiniteAcrossRepeatedSpends() public {
        uint256 approval = type(uint256).max - 1;
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), approval - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY - 1));
        assertEq(token.allowance(address(this), SPENDER), approval - SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revokingFiniteAndInfiniteApprovalsPreventsFurtherSpending() public {
        uint256[2] memory approvals = [SUPPLY, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(SPENDER, approvals[i]));
            vm.prank(SPENDER);
            assertTrue(token.transferFrom(address(this), ALICE, 1));
            assertTrue(token.approve(SPENDER, 0));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
            vm.prank(SPENDER);
            token.transferFrom(address(this), ALICE, 1);
            assertEq(token.allowance(address(this), SPENDER), 0);
            assertEq(token.balanceOf(ALICE), i + 1);
            assertEq(token.balanceOf(address(this)), SUPPLY - (i + 1));
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransfersStillRequireEnoughBalance() public {
        uint256 amount = SUPPLY + 1;
        bytes memory reason =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount);
        vm.expectRevert(reason);
        token.transfer(address(this), amount);

        assertTrue(token.approve(SPENDER, amount));
        vm.expectRevert(reason);
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(this), amount);
        assertEq(token.allowance(address(this), SPENDER), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferEmitsAndPreservesExistingAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 17));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 17);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroOwnerCannotMint() public {
        uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            // Both the owner and its allowance are invalid; error precedence is not the property.
            vm.expectRevert();
            vm.prank(SPENDER);
            token.transferFrom(address(0), ALICE, amounts[i]);
            assertEq(token.allowance(address(0), SPENDER), 0);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.balanceOf(ALICE), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_approvalIsIsolatedByOwnerAndCaller(uint256 approval) public {
        approval = bound(approval, 1, type(uint256).max);
        assertTrue(token.transfer(ALICE, 1));
        assertTrue(token.approve(SPENDER, approval));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB, SPENDER);
        token.transferFrom(address(this), BOB, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);

        assertEq(token.allowance(address(this), SPENDER), approval);
        assertEq(token.allowance(address(this), BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        vm.prank(SPENDER, BOB);
        assertTrue(token.transferFrom(address(this), BOB, 1));
        assertEq(token.allowance(address(this), SPENDER), approval == type(uint256).max ? approval : approval - 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacementAfterPartialSpendIsNotAdditive(uint256 spent, uint256 replacement) public {
        spent = bound(spent, 1, SUPPLY - 1);
        replacement = bound(replacement, 0, SUPPLY - spent - 1);
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));
        assertTrue(token.approve(SPENDER, replacement));
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);

        // The holder can afford this transfer, so only the replaced allowance can reject it.
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, replacement, replacement + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, replacement + 1);
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(BOB), 0);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, replacement));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent - replacement);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(BOB), replacement);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedDelegatedOverspendRollsBackApproval(uint256 held, uint256 amount, bool unlimited) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max);
        uint256 approval = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(ALICE, held));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroRecipientRollsBackFiniteOrInfiniteAllowance(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 approval = unlimited ? type(uint256).max : amount;
        assertTrue(token.approve(SPENDER, approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), SPENDER), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedTransfersMatchSingleTransfer(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        IMDUSD singleTransferToken = new IMDUSD();
        assertTrue(singleTransferToken.approve(SPENDER, total));
        vm.prank(SPENDER);
        assertTrue(singleTransferToken.transferFrom(address(this), ALICE, total));

        assertTrue(token.approve(SPENDER, total));
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertTrue(token.transferFrom(address(this), ALICE, total - first));
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.balanceOf(ALICE), singleTransferToken.balanceOf(ALICE));
        assertEq(token.balanceOf(address(this)), singleTransferToken.balanceOf(address(this)));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(singleTransferToken.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleTransferToken.totalSupply(), SUPPLY);
    }
}
