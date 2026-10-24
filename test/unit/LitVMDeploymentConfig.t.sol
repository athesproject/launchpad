// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { DeployBase } from "script/DeployBase.s.sol";
import { ChainIds } from "script/utils/ChainIds.sol";

/// @dev Exposes the deploy scripts' chain gate.
contract DeployBaseHarness is DeployBase {
    function load() external {
        _loadConfig(DEPLOYMENTS_CONFIG_PATH, false);
    }

    function deployChainId() external returns (uint256) {
        return _deployContext().chainId;
    }
}

/// @dev Audit ATH-10: LitVM (4441) is a testnet, and nothing new deployed from this config may be owned by the
///      original deployer account; owners are the LitVM 2-of-3 Safe.
contract LitVMDeploymentConfigTest is Test {
    address internal constant SAFE = 0x868b8B48db5DDE602D24960A606A5A8F93333bf9;
    address internal constant ORIGINAL_DEPLOYER = 0x23D542DCEFb00b1f4268E67a0EC1EF4de0A58fe2;

    function test_LitVMIsATestnetOwnedByTheSafe() public view {
        string memory toml = vm.readFile("deployments.config.toml");
        assertEq(ChainIds.LITVM_TESTNET, 4441);
        assertTrue(vm.parseTomlBool(toml, ".4441.bool.is_testnet"), "4441 is a testnet");
        assertEq(vm.parseTomlAddress(toml, ".4441.address.airlock_multisig"), SAFE, "Airlock owner");
        assertEq(vm.parseTomlAddress(toml, ".4441.address.deployer_owner"), SAFE, "deployer owner");
    }

    function test_NoConfigNamesTheOriginalDeployer() public view {
        string memory toml = vm.readFile("deployments.config.toml");
        assertFalse(vm.contains(vm.toLowercase(toml), vm.toLowercase(vm.toString(ORIGINAL_DEPLOYER))));
    }

    /// @dev A testnet deploys as configured; a production chain (Base) is refused unless the run is approved.
    function test_ProductionChainNeedsExplicitApproval() public {
        string[6] memory rpcUrls = [
            "BASE_MAINNET_RPC_URL",
            "BASE_SEPOLIA_RPC_URL",
            "ETH_MAINNET_RPC_URL",
            "LITVM_RPC_URL",
            "MONAD_MAINNET_RPC_URL",
            "ROBINHOOD_MAINNET_RPC_URL"
        ];
        for (uint256 i; i < rpcUrls.length; ++i) {
            vm.setEnv(rpcUrls[i], "http://127.0.0.1:8545");
        }
        DeployBaseHarness harness = new DeployBaseHarness();
        harness.load();
        vm.setEnv("DOPPLER_PRODUCTION_DEPLOY", "false");

        vm.chainId(ChainIds.LITVM_TESTNET);
        assertEq(harness.deployChainId(), ChainIds.LITVM_TESTNET, "testnet needs no approval");

        vm.chainId(8453);
        vm.expectRevert(bytes("production chain: set DOPPLER_PRODUCTION_DEPLOY=true to deploy"));
        harness.deployChainId();

        vm.setEnv("DOPPLER_PRODUCTION_DEPLOY", "true");
        assertEq(harness.deployChainId(), 8453, "approved production run");
        vm.setEnv("DOPPLER_PRODUCTION_DEPLOY", "false");
    }
}
