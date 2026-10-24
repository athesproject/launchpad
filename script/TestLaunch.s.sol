// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { Airlock, CreateParams } from "src/Airlock.sol";
import { ITokenFactory } from "src/interfaces/ITokenFactory.sol";
import { IGovernanceFactory } from "src/interfaces/IGovernanceFactory.sol";
import { IPoolInitializer } from "src/interfaces/IPoolInitializer.sol";
import { ILiquidityMigrator } from "src/interfaces/ILiquidityMigrator.sol";
import { BeneficiaryData } from "src/types/BeneficiaryData.sol";
import { VestingSchedule } from "src/tokens/DopplerERC20V1.sol";
import { InitData } from "src/initializers/LockableUniswapV3Initializer.sol";

contract TestLaunchScript is Script {
    function run() external {
        Airlock airlock = Airlock(payable(0x803CDD17e0be6652f407fe39e6779b93cfAb1c19));
        
        VestingSchedule[] memory schedules = new VestingSchedule[](0);
        address[] memory beneficiaries = new address[](0);
        uint256[] memory scheduleIds = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);
        address[] memory excluded = new address[](0);

        bytes memory tokenFactoryData = abi.encode(
            "TestToken",
            "TEST",
            schedules,
            beneficiaries,
            scheduleIds,
            amounts,
            "",
            uint256(0),
            uint48(0),
            address(0),
            excluded
        );

        bytes memory poolInitializerData = abi.encode(
            InitData({
                fee: 3000,
                tickLower: 167520,
                tickUpper: 200040,
                numPositions: 10,
                maxShareToBeSold: 0.23 ether,
                beneficiaries: new BeneficiaryData[](0)
            })
        );

        bytes memory migratorData = abi.encode(address(0), uint256(0));

        uint256 supply = 1_000_000_000 ether;

        CreateParams memory params = CreateParams({
            initialSupply: supply,
            numTokensToSell: supply,
            numeraire: 0x315374AA9b5536037Cc1Efeea2439CCC0913A77e,
            tokenFactory: ITokenFactory(0x2FACc7E98ec3181aef5381418840C2525777EbDd),
            tokenFactoryData: tokenFactoryData,
            governanceFactory: IGovernanceFactory(0xDC95a41583F95877586d94b68c783a0ce4Ce9b10),
            governanceFactoryData: "",
            poolInitializer: IPoolInitializer(0x026d005b37D8f7321C1642dC81F065457A1e3c16),
            poolInitializerData: poolInitializerData,
            liquidityMigrator: ILiquidityMigrator(0x5F133F8f1D4Ac24acAD7f04f913EA1c192B39760),
            liquidityMigratorData: migratorData,
            integrator: address(0),
            salt: keccak256(abi.encodePacked("test-token-salt-2"))
        });

        vm.startBroadcast(); // the --account / --sender given to forge script
        (address asset, address pool, address gov, address timelock, address migPool) = airlock.create(params);
        console.log("Token Created:", asset);
        console.log("V3 Pool:", pool);
        console.log("Governance:", gov);
        console.log("Timelock:", timelock);
        console.log("V2 Migration Pool:", migPool);
        vm.stopBroadcast();
    }
}
