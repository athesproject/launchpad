// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { console } from "forge-std/console.sol";
import { DeployBase } from "script/DeployBase.s.sol";
import { ChainIds } from "script/utils/ChainIds.sol";
import { Airlock } from "src/Airlock.sol";
import { DeployAirlock } from "script/deploy/DeployAirlock.s.sol";
import { DeployDopplerERC20V1Factory } from "script/deploy/DeployDopplerERC20V1Factory.s.sol";
import { DeployNoOpGovernanceFactory } from "script/deploy/DeployNoOpGovernanceFactory.s.sol";
import { DeployNoOpMigrator } from "script/deploy/DeployNoOpMigrator.s.sol";
import { DeployLockableUniswapV3Initializer } from "script/deploy/DeployLockableUniswapV3Initializer.s.sol";
import { DeployUniV2MigratorSplit } from "script/deploy/DeployUniV2MigratorSplit.s.sol";
import { DeployStreamableFeesLockerV2 } from "script/deploy/DeployStreamableFeesLockerV2.s.sol";
import { DeployTopUpDistributor } from "script/deploy/DeployTopUpDistributor.s.sol";

/// @notice Full deployment script for LitVM (chainId 4441)
/// @dev LitVM only has Uniswap V2 + V3. We use LockableUniswapV3Initializer instead of V4 hooks.
/// @dev Step 1: First deploy DopplerCreateXDeployer via DeployDopplerCreateXDeployer.s.sol, then run this script.
/// @dev Run with: forge script script/deploy/DeployLitVM.s.sol:DeployLitVMScript --rpc-url litvm --broadcast --private-key $DEPLOYER_PRIVATE_KEY
contract DeployLitVMScript is
    DeployAirlock,
    DeployDopplerERC20V1Factory,
    DeployNoOpGovernanceFactory,
    DeployNoOpMigrator,
    DeployLockableUniswapV3Initializer,
    DeployUniV2MigratorSplit,
    DeployStreamableFeesLockerV2,
    DeployTopUpDistributor
{
    function setUp() public {
        _loadConfigAndSelectFork(ChainIds.LITVM_MAINNET, false);
    }

    function run() public {
        DeployContext memory context = _deployContext();

        console.log("=== Deploying Doppler to LitVM (chainId: 4441) ===");
        console.log("Broadcaster:", context.broadcaster);
        console.log("Using LockableUniswapV3Initializer (no V4 on LitVM)");

        // 1. Deploy Airlock (the central registry / escrow)
        _deployAirlock(context);
        console.log("[1/8] Airlock deployed");

        // 2. Deploy DopplerERC20V1Factory (token factory)
        _deployDopplerERC20V1Factory(context);
        console.log("[2/8] DopplerERC20V1Factory deployed");

        // 3. Deploy StreamableFeesLockerV2 (fee management)
        _deployStreamableFeesLockerV2(context);
        console.log("[3/8] StreamableFeesLockerV2 deployed");

        // 4. Deploy TopUpDistributor
        _deployTopUpDistributor(context);
        console.log("[4/8] TopUpDistributor deployed");

        // 5. Deploy NoOpGovernanceFactory
        _deployNoOpGovernanceFactory(context);
        console.log("[5/8] NoOpGovernanceFactory deployed");

        // 6. Deploy NoOpMigrator
        _deployNoOpMigrator(context);
        console.log("[6/8] NoOpMigrator deployed");

        // 7. Deploy LockableUniswapV3Initializer (V3-based price discovery initializer)
        _deployLockableUniswapV3Initializer(context);
        console.log("[7/8] LockableUniswapV3Initializer deployed");

        // 8. Deploy UniV2MigratorSplit (for migrating liquidity to V2 after graduation)
        _deployUniV2MigratorSplit(context);
        console.log("[8/8] UniV2MigratorSplit deployed");

        console.log("=== LitVM Deployment Complete ===");
        console.log("Update Deployments.json with the new addresses!");
    }
}
