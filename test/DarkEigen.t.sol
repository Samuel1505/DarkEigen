// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";  
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {DarkEigenHook} from "../src/DarkEigen.sol";
import {HookMiner} from "./utils/HookMiner.sol"; 
import {IERC20} from "forge-std/interfaces/IERC20.sol";  

contract DarkEigenHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    DarkEigenHook hook;
    PoolId poolId;
    uint256 constant VALIDATOR_STAKE = 10 ether;
    address constant TRADER = address(0x1234);
    address constant VALIDATOR1 = address(0x5678);
    address constant VALIDATOR2 = address(0x9ABC);

    bytes constant EMPTY = "";

    function setUp() public {
        // Creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );

        // Encode both constructor args (PoolManager + initialOwner)
        bytes memory constructorArgs = abi.encode(manager, address(this));
        deployCodeTo("DarkEigenHook.sol:DarkEigenHook", constructorArgs, flags);
        hook = DarkEigenHook(flags);

        // Create the pool (using inherited key)
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        // Use literal for SQRT_PRICE_1_1
        manager.initialize(key, 79228162514264337593543950336);

        // Provide liquidity to the pool
        // Add salt (bytes32(0)) for ModifyLiquidityParams
        modifyLiquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-60, 60, 10 ether, bytes32(0)), EMPTY);
        modifyLiquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-120, 120, 10 ether, bytes32(0)), EMPTY);

        // Use IERC20 for approve (Currency.unwrap)
        IERC20(Currency.unwrap(currency0)).approve(address(manager), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(manager), type(uint256).max);
    }

    function testRegisterValidator() public {
        // Test validator registration
        vm.deal(VALIDATOR1, VALIDATOR_STAKE);
        vm.prank(VALIDATOR1);
        hook.registerValidator{value: VALIDATOR_STAKE}(VALIDATOR_STAKE);

        // Check validator was registered
        (address validator, uint256 stake, bool isActive, uint256 slashingRisk) = hook.avsValidators(VALIDATOR1);
        assertEq(validator, VALIDATOR1);
        assertEq(stake, VALIDATOR_STAKE);
        assertTrue(isActive);
        assertEq(slashingRisk, 0);
        assertEq(hook.getTotalStake(), VALIDATOR_STAKE);
    }

    function testValidatorSlashing() public {
        // Register validator first
        vm.deal(VALIDATOR1, VALIDATOR_STAKE);
        vm.prank(VALIDATOR1);
        hook.registerValidator{value: VALIDATOR_STAKE}(VALIDATOR_STAKE);

        // Slash validator (no prank needed: test contract is owner)
        uint256 slashAmount = 2 ether;
        hook.slashValidator(VALIDATOR1, slashAmount);

        // Check slashing result
        (, uint256 stake, bool isActive, uint256 slashingRisk) = hook.avsValidators(VALIDATOR1);
        assertEq(stake, VALIDATOR_STAKE - slashAmount);
        assertTrue(isActive);
        assertEq(slashingRisk, slashAmount);
        assertEq(hook.getTotalStake(), VALIDATOR_STAKE - slashAmount);
    }

    function testCommitRevealOrder() public {
        // Setup
        uint256 amount = 1 ether;
        uint256 minAmountOut = 0.95 ether;
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = 123;

        // Generate order hash
        bytes32 orderHash = keccak256(abi.encodePacked(
            TRADER, amount, minAmountOut, deadline, nonce
        ));

        // Test commit phase
        vm.prank(TRADER);
        hook.commitOrder(orderHash);

        // Check order was committed
        (bytes32 hash, address trader, , , , bool isExecuted, uint256 commitBlock) = hook.privateOrders(orderHash);
        assertEq(hash, orderHash);
        assertEq(trader, TRADER);
        assertFalse(isExecuted);
        assertEq(commitBlock, block.number);

        // Fast forward to satisfy MEV protection delay
        vm.roll(block.number + hook.MIN_COMMIT_BLOCKS() + 1);

        // FIXED: Transfer from this (test contract) to TRADER
        currency0.transfer(TRADER, amount);
        vm.prank(TRADER);
        IERC20(Currency.unwrap(currency0)).approve(address(manager), amount);

        // Prepare swap parameters
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(uint256(amount)),  // Positive for exactIn
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Test reveal and execute (should succeed)
        vm.prank(TRADER);
        hook.revealAndExecuteOrder(
            orderHash,
            amount,
            minAmountOut,
            deadline,
            nonce,
            key,
            params
        );

        // Check order was executed
        (, , , , , bool executed, ) = hook.privateOrders(orderHash);
        assertTrue(executed);
    }

    function testCrossChainSwapInitiation() public {
        uint256 targetChain = 137; // Polygon
        address sourceToken = Currency.unwrap(currency0);
        address targetToken = Currency.unwrap(currency1);
        uint256 amount = 1 ether;
        address recipient = TRADER;
        bytes32 proofHash = keccak256("test_proof");

        // FIXED: Transfer from this (test contract) to TRADER
        IERC20(sourceToken).transfer(TRADER, amount);

        // Initiate cross-chain swap (approves to hook)
        vm.prank(TRADER);
        IERC20(sourceToken).approve(address(hook), amount);
        vm.prank(TRADER);
        bytes32 swapHash = hook.initiateCrossChainSwap(
            targetChain,
            sourceToken,
            targetToken,
            amount,
            recipient,
            proofHash
        );

        // Check swap was initiated
        (
            uint256 sourceChain,
            uint256 targetChainStored,
            address sourceTokenStored,
            address targetTokenStored,
            uint256 amountStored,
            address recipientStored,
            bytes32 proofHashStored,
            bool isCompleted
        ) = hook.crossChainSwaps(swapHash);
        assertEq(sourceChain, block.chainid);
        assertEq(targetChainStored, targetChain);
        assertEq(sourceTokenStored, sourceToken);
        assertEq(targetTokenStored, targetToken);
        assertEq(amountStored, amount);
        assertEq(recipientStored, recipient);
        assertEq(proofHashStored, proofHash);
        assertFalse(isCompleted);

        // Check tokens were locked
        assertEq(IERC20(sourceToken).balanceOf(address(hook)), amount);
    }

    function testMEVProtection() public {
        uint256 amount = 1 ether;
        uint256 minAmountOut = 0.95 ether;
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = 456;

        bytes32 orderHash = keccak256(abi.encodePacked(
            TRADER, amount, minAmountOut, deadline, nonce
        ));

        vm.prank(TRADER);
        hook.commitOrder(orderHash);

        // FIXED: Transfer from this (test contract) to TRADER
        currency0.transfer(TRADER, amount);
        vm.prank(TRADER);
        IERC20(Currency.unwrap(currency0)).approve(address(manager), amount);

        // Prepare params
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(uint256(amount)),  // Positive for exactIn
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Try to execute immediately (should fail due to MEV protection)
        vm.prank(TRADER);
        vm.expectRevert("Too early to execute");
        hook.revealAndExecuteOrder(
            orderHash,
            amount,
            minAmountOut,
            deadline,
            nonce,
            key,
            params
        );
    }

    function testGetActiveValidators() public {
        // Register multiple validators
        vm.deal(VALIDATOR1, VALIDATOR_STAKE);
        vm.deal(VALIDATOR2, VALIDATOR_STAKE);
        vm.prank(VALIDATOR1);
        hook.registerValidator{value: VALIDATOR_STAKE}(VALIDATOR_STAKE);
        vm.prank(VALIDATOR2);
        hook.registerValidator{value: VALIDATOR_STAKE}(VALIDATOR_STAKE);

        // Get active validators
        address[] memory activeValidators = hook.getActiveValidators();
        assertEq(activeValidators.length, 2);
        assertEq(activeValidators[0], VALIDATOR1);
        assertEq(activeValidators[1], VALIDATOR2);

        // Slash one validator completely
        hook.slashValidator(VALIDATOR1, VALIDATOR_STAKE);

        // Check active validators again
        activeValidators = hook.getActiveValidators();
        assertEq(activeValidators.length, 1);
        assertEq(activeValidators[0], VALIDATOR2);
    }

    function testSwapWithEnabledPool() public {
        // Test that swaps work with enabled pools (using inherited swap)
        // Use inherited swap directly; positive for exactIn
        bool zeroForOne = true;
        int256 amountSpecified = int256(1e18);  // Positive exactIn
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, EMPTY);

        // Assert negative delta for input (zeroForOne exactIn)
        assertEq(int256(swapDelta.amount0()), -amountSpecified);
    }

    function testFailSwapWithDisabledPool() public {
        // Create second pool WITH hook (init enables it), then disable via storage hack
        PoolKey memory disabledKey = PoolKey(currency0, currency1, 3000, 61, IHooks(hook));  // Different hook salt
        PoolId disabledPoolId = disabledKey.toId();
        // Use literal for SQRT_PRICE_1_1
        manager.initialize(disabledKey, 79228162514264337593543950336);

        // Provide liquidity
        modifyLiquidityRouter.modifyLiquidity(disabledKey, ModifyLiquidityParams(-60, 60, 10 ether, bytes32(0)), EMPTY);

        // Force disable enabledPools[poolId] = false (mapping at slot 3)
        bytes32 enabledSlot = keccak256(abi.encode(disabledPoolId, uint256(3)));
        vm.store(address(hook), enabledSlot, bytes32(uint256(0)));

        // Now swap should revert from hook's require
        vm.expectRevert("Pool not enabled for DarkEigen");
        swap(disabledKey, true, int256(1e18), EMPTY);
    }
}