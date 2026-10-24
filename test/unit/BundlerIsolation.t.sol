// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { UniversalRouter } from "@universal-router/UniversalRouter.sol";
import { IQuoterV2 } from "@v3-periphery/interfaces/IQuoterV2.sol";
import { IHooks } from "@v4-core/interfaces/IHooks.sol";
import { TestERC20 } from "@v4-core/test/TestERC20.sol";
import { Currency } from "@v4-core/types/Currency.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";
import { IV4Quoter } from "@v4-periphery/interfaces/IV4Quoter.sol";
import { Test } from "forge-std/Test.sol";
import { Airlock, CreateParams } from "src/Airlock.sol";
import { Bundler, InvalidOutputToken, OnlySelf } from "src/Bundler.sol";
import { IGovernanceFactory } from "src/interfaces/IGovernanceFactory.sol";
import { ILiquidityMigrator } from "src/interfaces/ILiquidityMigrator.sol";
import { IPoolInitializer } from "src/interfaces/IPoolInitializer.sol";
import { ITokenFactory } from "src/interfaces/ITokenFactory.sol";

/// @dev Creates a fresh token on every call, like the Airlock creates an asset.
contract MockAirlockForBundler {
    uint256 public creates;
    address public lastAsset;

    function create(CreateParams calldata) external returns (address, address, address, address, address) {
        ++creates;
        lastAsset = address(new TestERC20(0));
        return (lastAsset, address(0), address(0), address(0), address(0));
    }
}

/// @dev Stands in for the Universal Router: records the value it got and pays back what the test configures.
contract MockRouterForBundler {
    MockAirlockForBundler public immutable airlock;
    uint256 public lastValue;
    uint256 public assetOut;
    uint256 public ethBack;
    TestERC20 public numeraire;
    uint256 public numeraireBack;

    constructor(MockAirlockForBundler airlock_) {
        airlock = airlock_;
    }

    function configure(uint256 assetOut_, uint256 ethBack_, TestERC20 numeraire_, uint256 numeraireBack_) external {
        (assetOut, ethBack, numeraire, numeraireBack) = (assetOut_, ethBack_, numeraire_, numeraireBack_);
    }

    function execute(bytes calldata, bytes[] calldata) external payable {
        lastValue = msg.value;
        if (assetOut > 0) TestERC20(airlock.lastAsset()).mint(msg.sender, assetOut);
        if (numeraireBack > 0) numeraire.mint(msg.sender, numeraireBack);
        if (ethBack > 0) {
            (bool ok,) = msg.sender.call{ value: ethBack }("");
            require(ok, "eth back");
        }
    }
}

contract MockQuoterV2ForBundler {
    function quoteExactInputSingle(IQuoterV2.QuoteExactInputSingleParams memory)
        external
        pure
        returns (uint256, uint160, uint32, uint256)
    {
        return (42, 0, 0, 0);
    }

    function quoteExactOutputSingle(IQuoterV2.QuoteExactOutputSingleParams memory)
        external
        pure
        returns (uint256, uint160, uint32, uint256)
    {
        return (24, 0, 0, 0);
    }
}

contract MockV4QuoterForBundler {
    function quoteExactInputSingle(IV4Quoter.QuoteExactSingleParams memory) external pure returns (uint256, uint256) {
        return (7, 1);
    }

    function quoteExactOutputSingle(IV4Quoter.QuoteExactSingleParams memory) external pure returns (uint256, uint256) {
        return (8, 2);
    }
}

/// @dev The pool initializer's getState getter: the asset is currency0 of its pool.
contract MockPoolInitializerForBundler {
    address public immutable numeraire;

    constructor(address numeraire_) {
        numeraire = numeraire_;
    }

    function getState(address asset)
        external
        view
        returns (address, uint256, address, bytes memory, uint8, PoolKey memory, int24)
    {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(asset),
            currency1: Currency.wrap(numeraire),
            fee: 0,
            tickSpacing: 1,
            hooks: IHooks(address(0))
        });
        return (numeraire, 0, address(0), "", 2, key, 0);
    }
}

contract BundlerIsolationTest is Test {
    MockAirlockForBundler internal airlock;
    MockRouterForBundler internal router;
    MockPoolInitializerForBundler internal poolInitializer;
    TestERC20 internal numeraire;
    Bundler internal bundler;
    address internal user = makeAddr("user");

    function setUp() public {
        airlock = new MockAirlockForBundler();
        router = new MockRouterForBundler(airlock);
        numeraire = new TestERC20(0);
        poolInitializer = new MockPoolInitializerForBundler(address(numeraire));
        bundler = new Bundler(
            Airlock(payable(address(airlock))),
            UniversalRouter(payable(address(router))),
            IQuoterV2(address(new MockQuoterV2ForBundler())),
            IV4Quoter(address(new MockV4QuoterForBundler()))
        );
        vm.deal(user, 100 ether);
        vm.deal(address(router), 100 ether);
    }

    function _createParams() internal view returns (CreateParams memory) {
        return CreateParams({
            initialSupply: 1e27,
            numTokensToSell: 1e27,
            numeraire: address(numeraire),
            tokenFactory: ITokenFactory(address(0)),
            tokenFactoryData: "",
            governanceFactory: IGovernanceFactory(address(0)),
            governanceFactoryData: "",
            poolInitializer: IPoolInitializer(address(poolInitializer)),
            poolInitializerData: "",
            liquidityMigrator: ILiquidityMigrator(address(0)),
            liquidityMigratorData: "",
            integrator: address(0),
            salt: bytes32(0)
        });
    }

    function _prefund() internal {
        vm.deal(address(bundler), 5 ether);
        numeraire.mint(address(bundler), 1000 ether);
    }

    function _assertPrefundUntouched() internal view {
        assertEq(address(bundler).balance, 5 ether, "prefunded ETH");
        assertEq(numeraire.balanceOf(address(bundler)), 1000 ether, "prefunded numeraire");
    }

    // ── ATH-04: bundle only uses and returns what this call brought ──

    function test_bundle_ForwardsOnlyMsgValue() public {
        _prefund();
        vm.prank(user);
        bundler.bundle{ value: 1 ether }(_createParams(), "", new bytes[](0));
        assertEq(router.lastValue(), 1 ether, "router got msg.value, not the Bundler's balance");
        _assertPrefundUntouched();
    }

    /// @dev The Bundler has no receive(), so the router cannot send ETH back; the prefunded ETH stands in for
    ///      ETH forced in, and must stay.
    function test_bundle_ReturnsOnlyThisCallsLeftovers() public {
        _prefund();
        router.configure(50 ether, 0, numeraire, 10 ether);
        uint256 ethBefore = user.balance;
        vm.prank(user);
        bundler.bundle{ value: 1 ether }(_createParams(), "", new bytes[](0));
        assertEq(TestERC20(airlock.lastAsset()).balanceOf(user), 50 ether, "bought asset");
        assertEq(numeraire.balanceOf(user), 10 ether, "numeraire left over by this call");
        assertEq(ethBefore - user.balance, 1 ether, "the user paid exactly msg.value");
        _assertPrefundUntouched();
    }

    function test_bundle_CannotSweepPrefundedBalances() public {
        _prefund();
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        bundler.bundle(_createParams(), "", new bytes[](0));
        assertEq(numeraire.balanceOf(attacker), 0);
        assertEq(attacker.balance, 0);
        _assertPrefundUntouched();
    }

    // ── ATH-09: simulations leave nothing behind, even as transactions ──

    function _quoteParamsIn() internal view returns (IQuoterV2.QuoteExactInputSingleParams memory) {
        address predicted = vm.computeCreateAddress(address(airlock), vm.getNonce(address(airlock)));
        return IQuoterV2.QuoteExactInputSingleParams(address(numeraire), predicted, 1 ether, 3000, 0);
    }

    function _assertNothingPersisted(address predicted, uint256 nonceBefore) internal view {
        assertEq(airlock.creates(), 0, "no create persisted");
        assertEq(predicted.code.length, 0, "no asset code persisted");
        assertEq(vm.getNonce(address(airlock)), nonceBefore, "no nonce consumed");
    }

    function test_simulateBundleExactIn_SentAsTransaction() public {
        IQuoterV2.QuoteExactInputSingleParams memory params = _quoteParamsIn();
        uint256 nonceBefore = vm.getNonce(address(airlock));
        vm.prank(user);
        assertEq(bundler.simulateBundleExactIn(_createParams(), params), 42);
        _assertNothingPersisted(params.tokenOut, nonceBefore);
    }

    function test_simulateBundleExactOut_SentAsTransaction() public {
        address predicted = vm.computeCreateAddress(address(airlock), vm.getNonce(address(airlock)));
        uint256 nonceBefore = vm.getNonce(address(airlock));
        vm.prank(user);
        uint256 amountIn = bundler.simulateBundleExactOut(
            _createParams(), IQuoterV2.QuoteExactOutputSingleParams(address(numeraire), predicted, 1 ether, 3000, 0)
        );
        assertEq(amountIn, 24);
        _assertNothingPersisted(predicted, nonceBefore);
    }

    function test_simulateMulticurve_SentAsTransaction() public {
        address predicted = vm.computeCreateAddress(address(airlock), vm.getNonce(address(airlock)));
        uint256 nonceBefore = vm.getNonce(address(airlock));

        vm.prank(user);
        (address asset, PoolKey memory key, uint256 amountOut, uint256 gas) =
            bundler.simulateMulticurveBundleExactIn(_createParams(), 1 ether, "");
        assertEq(asset, predicted);
        assertEq(Currency.unwrap(key.currency0), predicted);
        assertEq(Currency.unwrap(key.currency1), address(numeraire));
        assertEq(amountOut, 7);
        assertEq(gas, 1);

        vm.prank(user);
        uint256 amountIn;
        (asset,, amountIn, gas) = bundler.simulateMulticurveBundleExactOut(_createParams(), 0, "");
        assertEq(asset, predicted);
        assertEq(amountIn, 8);
        assertEq(gas, 2);
        _assertNothingPersisted(predicted, nonceBefore);
    }

    function test_simulate_PassesOnStepErrors() public {
        IQuoterV2.QuoteExactInputSingleParams memory params = _quoteParamsIn();
        params.tokenOut = makeAddr("not the asset");
        vm.expectRevert(InvalidOutputToken.selector);
        bundler.simulateBundleExactIn(_createParams(), params);
    }

    function test_simulationSteps_OnlyCallableByTheBundler() public {
        vm.expectRevert(OnlySelf.selector);
        bundler.simulationStepExactIn(_createParams(), _quoteParamsIn());
        vm.expectRevert(OnlySelf.selector);
        bundler.simulationStepMulticurveExactIn(_createParams(), 1 ether, "");
    }
}
