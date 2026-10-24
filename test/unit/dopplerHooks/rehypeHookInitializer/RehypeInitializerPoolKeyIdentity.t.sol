// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IHooks } from "@v4-core/interfaces/IHooks.sol";
import { IPoolManager } from "@v4-core/interfaces/IPoolManager.sol";
import { Currency } from "@v4-core/types/Currency.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";
import { Test } from "forge-std/Test.sol";
import { RehypeDopplerHookInitializer } from "src/dopplerHooks/RehypeDopplerHookInitializer.sol";
import { BeneficiaryData } from "src/types/BeneficiaryData.sol";
import {
    FeeDistributionInfo,
    FeeRoutingMode,
    InitData,
    InvalidAsset,
    InvalidNumeraire
} from "src/types/RehypeTypes.sol";
import { WAD } from "src/types/Wad.sol";
import {
    MockInitializer,
    MockPoolManager
} from "test/unit/dopplerHooks/rehypeHookInitializer/RehypeDopplerHookInitializer.t.sol";

/**
 * @dev Audit ATH-03: the initializer hook takes the numeraire from the PoolKey, as upstream Doppler does since
 *      ae638a9a. A mismatch or an asset that is not in the key reverts before anything is stored.
 */
contract RehypeInitializerPoolKeyIdentityTest is Test {
    MockInitializer internal initializer;
    RehypeDopplerHookInitializer internal hook;
    address internal token0 = address(0x1000);
    address internal token1 = address(0x2000);
    PoolKey internal key;

    function setUp() public {
        initializer = new MockInitializer();
        hook = new RehypeDopplerHookInitializer(address(initializer), IPoolManager(address(new MockPoolManager())));
        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function _initData(address numeraire) internal returns (bytes memory) {
        return abi.encode(
            InitData({
                numeraire: numeraire,
                buybackDst: makeAddr("buybackDst"),
                startFee: 3000,
                endFee: 3000,
                durationSeconds: 0,
                startingTime: 0,
                feeRoutingMode: FeeRoutingMode.DirectBuyback,
                feeDistributionInfo: FeeDistributionInfo({
                    assetFeesToAssetBuybackWad: WAD,
                    assetFeesToNumeraireBuybackWad: 0,
                    assetFeesToBeneficiaryWad: 0,
                    assetFeesToLpWad: 0,
                    numeraireFeesToAssetBuybackWad: 0,
                    numeraireFeesToNumeraireBuybackWad: WAD,
                    numeraireFeesToBeneficiaryWad: 0,
                    numeraireFeesToLpWad: 0
                }),
                feeBeneficiaries: new BeneficiaryData[](0)
            })
        );
    }

    function test_onInitialization_RevertsOnNumeraireMismatch(address wrongNumeraire) public {
        vm.assume(wrongNumeraire != token1);
        vm.prank(address(initializer));
        vm.expectRevert(abi.encodeWithSelector(InvalidNumeraire.selector, token1, wrongNumeraire));
        hook.onInitialization(token0, key, _initData(wrongNumeraire));

        (address storedAsset,,) = hook.getPoolInfo(key.toId());
        assertEq(storedAsset, address(0), "nothing stored");
    }

    function test_onInitialization_RevertsWhenAssetIsNotInTheKey(address stranger) public {
        vm.assume(stranger != token0 && stranger != token1);
        vm.prank(address(initializer));
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector, stranger));
        hook.onInitialization(stranger, key, _initData(token1));

        (address storedAsset,,) = hook.getPoolInfo(key.toId());
        assertEq(storedAsset, address(0), "nothing stored");
    }

    function test_onInitialization_AcceptsEitherOrder(bool assetIsToken0) public {
        address asset = assetIsToken0 ? token0 : token1;
        address numeraire = assetIsToken0 ? token1 : token0;
        vm.prank(address(initializer));
        hook.onInitialization(asset, key, _initData(numeraire));
        (address storedAsset, address storedNumeraire,) = hook.getPoolInfo(key.toId());
        assertEq(storedAsset, asset);
        assertEq(storedNumeraire, numeraire);
    }
}
