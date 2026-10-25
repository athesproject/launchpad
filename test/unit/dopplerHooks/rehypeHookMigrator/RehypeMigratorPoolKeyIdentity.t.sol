// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IHooks } from "@v4-core/interfaces/IHooks.sol";
import { IPoolManager } from "@v4-core/interfaces/IPoolManager.sol";
import { TestERC20 } from "@v4-core/test/TestERC20.sol";
import { toBalanceDelta } from "@v4-core/types/BalanceDelta.sol";
import { Currency } from "@v4-core/types/Currency.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";
import { Test } from "forge-std/Test.sol";
import { RehypeDopplerHookMigrator } from "src/dopplerHooks/RehypeDopplerHookMigrator.sol";
import { DopplerHookMigrator } from "src/migrators/DopplerHookMigrator.sol";
import {
    FeeDistributionInfo,
    FeeRoutingMode,
    InvalidAsset,
    InvalidNumeraire,
    MigratorInitData
} from "src/types/RehypeTypes.sol";
import { WAD } from "src/types/Wad.sol";
import {
    MigratorTrackingPoolManager,
    MockMigratorForRehype
} from "test/unit/dopplerHooks/rehypeHookMigrator/RehypeDopplerHookMigrator.t.sol";

/**
 * @dev Audit ATH-01: the migrator stores the PoolKey currency paired with the asset as the numeraire, rejects any
 *      other value, and keeps each pool's payouts in that pool's own currencies.
 */
contract RehypeMigratorPoolKeyIdentityTest is Test {
    MockMigratorForRehype internal mockMigrator;
    MigratorTrackingPoolManager internal poolManager;
    RehypeDopplerHookMigrator internal hook;
    TestERC20 internal asset; // pool A asset, currency0
    TestERC20 internal numeraire; // pool A numeraire, currency1
    TestERC20 internal otherPoolToken; // held by the hook for another pool
    PoolKey internal keyA;
    address internal recipient = makeAddr("buybackDst");

    function setUp() public {
        mockMigrator = new MockMigratorForRehype(makeAddr("AirlockOwner"));
        poolManager = new MigratorTrackingPoolManager();
        hook = new RehypeDopplerHookMigrator(
            DopplerHookMigrator(payable(address(mockMigrator))), IPoolManager(address(poolManager))
        );

        TestERC20 t0 = new TestERC20(type(uint128).max);
        TestERC20 t1 = new TestERC20(type(uint128).max);
        (asset, numeraire) = address(t0) < address(t1) ? (t0, t1) : (t1, t0);
        otherPoolToken = new TestERC20(type(uint128).max);
        keyA = PoolKey({
            currency0: Currency.wrap(address(asset)),
            currency1: Currency.wrap(address(numeraire)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        asset.transfer(address(poolManager), 1000 ether);
        numeraire.transfer(address(poolManager), 1000 ether);
        otherPoolToken.transfer(address(hook), 100 ether);
    }

    /// @dev Every numeraire fee goes straight to `recipient` as a numeraire buyback.
    function _directNumeraireBuyback(address numeraire_) internal view returns (bytes memory) {
        return abi.encode(
            MigratorInitData({
                numeraire: numeraire_,
                buybackDst: recipient,
                customFee: 10_000,
                feeRoutingMode: FeeRoutingMode.DirectBuyback,
                feeDistributionInfo: FeeDistributionInfo({
                    assetFeesToAssetBuybackWad: uint64(WAD),
                    assetFeesToNumeraireBuybackWad: 0,
                    assetFeesToBeneficiaryWad: 0,
                    assetFeesToLpWad: 0,
                    numeraireFeesToAssetBuybackWad: 0,
                    numeraireFeesToNumeraireBuybackWad: uint64(WAD),
                    numeraireFeesToBeneficiaryWad: 0,
                    numeraireFeesToLpWad: 0
                })
            })
        );
    }

    function test_onInitialization_RevertsWhenNumeraireIsAnotherToken() public {
        vm.prank(address(mockMigrator));
        vm.expectRevert(abi.encodeWithSelector(InvalidNumeraire.selector, address(numeraire), address(otherPoolToken)));
        hook.onInitialization(address(asset), keyA, _directNumeraireBuyback(address(otherPoolToken)));

        (address storedAsset, address storedNumeraire,) = hook.getPoolInfo(keyA.toId());
        assertEq(storedAsset, address(0), "nothing stored");
        assertEq(storedNumeraire, address(0), "nothing stored");
    }

    function test_onInitialization_RevertsWhenAssetIsNotInTheKey() public {
        vm.prank(address(mockMigrator));
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector, address(otherPoolToken)));
        hook.onInitialization(address(otherPoolToken), keyA, _directNumeraireBuyback(address(numeraire)));
    }

    function test_onInitialization_StoresTheKeysNumeraire(bool assetIsToken0) public {
        PoolKey memory key = keyA;
        address asset_ = assetIsToken0 ? address(asset) : address(numeraire);
        address numeraire_ = assetIsToken0 ? address(numeraire) : address(asset);
        vm.prank(address(mockMigrator));
        hook.onInitialization(asset_, key, _directNumeraireBuyback(numeraire_));
        (address storedAsset, address storedNumeraire,) = hook.getPoolInfo(key.toId());
        assertEq(storedAsset, asset_);
        assertEq(storedNumeraire, numeraire_);
    }

    /// @dev Pool A pays out its fees many times; the other pool's tokens in the shared hook never move.
    function test_twoPools_PoolAActivityNeverMovesAnotherPoolsTokens() public {
        vm.prank(address(mockMigrator));
        hook.onInitialization(address(asset), keyA, _directNumeraireBuyback(address(numeraire)));

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({ zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0 });
        for (uint256 i; i < 5; ++i) {
            vm.prank(address(mockMigrator));
            hook.onAfterSwap(address(0x1234), keyA, params, toBalanceDelta(-1 ether, 5 ether), "");
        }

        assertGt(numeraire.balanceOf(recipient), 0, "pool A paid its buyback in its own numeraire");
        assertEq(otherPoolToken.balanceOf(recipient), 0, "nothing paid in another pool's token");
        assertEq(otherPoolToken.balanceOf(address(hook)), 100 ether, "the other pool's balance is untouched");
    }
}
