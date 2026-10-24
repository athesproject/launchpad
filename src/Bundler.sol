// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { UniversalRouter } from "@universal-router/UniversalRouter.sol";
import { IQuoterV2 } from "@v3-periphery/interfaces/IQuoterV2.sol";
import { Currency } from "@v4-core/types/Currency.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";
import { IV4Quoter } from "@v4-periphery/interfaces/IV4Quoter.sol";
import { Airlock, CreateParams } from "src/Airlock.sol";
import { DopplerHookInitializer } from "src/initializers/DopplerHookInitializer.sol";

/// @dev Thrown when an invalid address is passed as a contructor parameter
error InvalidAddresses();

/// @dev Thrown when the asset address doesn't match the predicted one
error InvalidOutputToken();

/// @dev Thrown when the amount to quote exceeds the uint128 limit
error ExactAmountTooLarge();

/// @dev Thrown when the asset is not part of the resulting pool
error AssetNotInPool();

/// @dev Thrown when the provided exact amount is zero
error ExactAmountZero();

/// @dev Thrown by a simulation step to hand back its result; the revert undoes everything the step did
error SimulationResult(bytes result);

/// @dev Thrown when a simulation step is called by anyone but this contract
error OnlySelf();

/**
 * @author Whetstone
 * @custom:security-contact security@whetstone.cc
 */
contract Bundler {
    /// @notice Address of the Airlock contract
    Airlock public immutable airlock;

    /// @notice Address of the Universal Router contract
    UniversalRouter public immutable router;

    /// @notice Address of the QuoterV2 contract
    IQuoterV2 public immutable quoter;

    /// @notice Address of the Uniswap V4 Quoter contract
    IV4Quoter public immutable v4Quoter;

    /**
     * @param airlock_ Immutable address of the Airlock contract
     * @param router_ Immutable address of the Universal Router contract
     * @param quoter_ Immutable address of the QuoterV2 contract
     */
    constructor(Airlock airlock_, UniversalRouter router_, IQuoterV2 quoter_, IV4Quoter v4Quoter_) {
        if (
            address(airlock_) == address(0) || address(router_) == address(0) || address(quoter_) == address(0)
                || address(v4Quoter_) == address(0)
        ) {
            revert InvalidAddresses();
        }

        airlock = Airlock(airlock_);
        router = UniversalRouter(router_);
        quoter = IQuoterV2(quoter_);
        v4Quoter = IV4Quoter(v4Quoter_);
    }

    /*
     * Simulations create the asset and quote the buy inside a self-call that always reverts, so nothing they do
     * persists, even when they are sent as a transaction instead of an eth_call (audit ATH-09).
     */

    /**
     * @notice Simulates a bundle operation with an exact output amount
     * @param createData Creation data to pass to the Airlock contract
     * @param params Exact output parameters to pass to the QuoterV2 contract
     * @return amountIn Amount of input token required to receive the exact output amount
     */
    function simulateBundleExactOut(
        CreateParams calldata createData,
        IQuoterV2.QuoteExactOutputSingleParams calldata params
    ) external returns (uint256 amountIn) {
        amountIn = abi.decode(_simulate(abi.encodeCall(this.simulationStepExactOut, (createData, params))), (uint256));
    }

    /**
     * @notice Simulates a bundle operation with an exact input amount
     * @param createData Creation data to pass to the Airlock contract
     * @param params Exact input parameters to pass to the QuoterV2 contract
     * @return amountOut Amount of output token received from the exact input amount
     */
    function simulateBundleExactIn(
        CreateParams calldata createData,
        IQuoterV2.QuoteExactInputSingleParams calldata params
    ) external returns (uint256 amountOut) {
        amountOut = abi.decode(_simulate(abi.encodeCall(this.simulationStepExactIn, (createData, params))), (uint256));
    }

    /**
     * @notice Simulates a multicurve bundle, returning the pool key and the quote to purchase the issued tokens
     * @param createData Creation data to pass to the Airlock contract
     * @return asset Address of the created asset token
     * @return poolKey PoolKey associated with the initialized Uniswap V4 pool
     * @return amountIn Numeraire required to receive the requested asset amount
     * @return gasEstimate Estimated gas for the swap quote
     */
    function simulateMulticurveBundleExactOut(
        CreateParams calldata createData,
        uint128 exactAmountOut,
        bytes calldata hookData
    ) external returns (address asset, PoolKey memory poolKey, uint256 amountIn, uint256 gasEstimate) {
        (asset, poolKey, amountIn, gasEstimate) = abi.decode(
            _simulate(abi.encodeCall(this.simulationStepMulticurveExactOut, (createData, exactAmountOut, hookData))),
            (address, PoolKey, uint256, uint256)
        );
    }

    function simulateMulticurveBundleExactIn(
        CreateParams calldata createData,
        uint128 exactAmountIn,
        bytes calldata hookData
    ) external returns (address asset, PoolKey memory poolKey, uint256 amountOut, uint256 gasEstimate) {
        if (exactAmountIn == 0) revert ExactAmountZero();
        (asset, poolKey, amountOut, gasEstimate) = abi.decode(
            _simulate(abi.encodeCall(this.simulationStepMulticurveExactIn, (createData, exactAmountIn, hookData))),
            (address, PoolKey, uint256, uint256)
        );
    }

    /// @dev Simulation step of simulateBundleExactOut; only this contract may call it, and it always reverts
    function simulationStepExactOut(
        CreateParams calldata createData,
        IQuoterV2.QuoteExactOutputSingleParams calldata params
    ) external {
        if (msg.sender != address(this)) revert OnlySelf();
        (address asset,,,,) = airlock.create(createData);
        if (asset != params.tokenOut) {
            revert InvalidOutputToken();
        }
        (uint256 amountIn,,,) = quoter.quoteExactOutputSingle(params);
        revert SimulationResult(abi.encode(amountIn));
    }

    /// @dev Simulation step of simulateBundleExactIn; only this contract may call it, and it always reverts
    function simulationStepExactIn(
        CreateParams calldata createData,
        IQuoterV2.QuoteExactInputSingleParams calldata params
    ) external {
        if (msg.sender != address(this)) revert OnlySelf();
        (address asset,,,,) = airlock.create(createData);
        if (asset != params.tokenOut) {
            revert InvalidOutputToken();
        }
        (uint256 amountOut,,,) = quoter.quoteExactInputSingle(params);
        revert SimulationResult(abi.encode(amountOut));
    }

    /// @dev Simulation step of simulateMulticurveBundleExactOut; only this contract may call it, and it always reverts
    function simulationStepMulticurveExactOut(
        CreateParams calldata createData,
        uint128 exactAmountOut,
        bytes calldata hookData
    ) external {
        if (msg.sender != address(this)) revert OnlySelf();
        (address asset, PoolKey memory poolKey, bool zeroForOne) = _prepareMulticurveQuote(createData);

        uint128 amount = _resolveExactOutAmount(createData, exactAmountOut);

        (uint256 amountIn, uint256 gasEstimate) = v4Quoter.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: poolKey, zeroForOne: zeroForOne, exactAmount: amount, hookData: hookData
            })
        );
        revert SimulationResult(abi.encode(asset, poolKey, amountIn, gasEstimate));
    }

    /// @dev Simulation step of simulateMulticurveBundleExactIn; only this contract may call it, and it always reverts
    function simulationStepMulticurveExactIn(
        CreateParams calldata createData,
        uint128 exactAmountIn,
        bytes calldata hookData
    ) external {
        if (msg.sender != address(this)) revert OnlySelf();
        (address asset, PoolKey memory poolKey, bool zeroForOne) = _prepareMulticurveQuote(createData);

        (uint256 amountOut, uint256 gasEstimate) = v4Quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: poolKey, zeroForOne: zeroForOne, exactAmount: exactAmountIn, hookData: hookData
            })
        );
        revert SimulationResult(abi.encode(asset, poolKey, amountOut, gasEstimate));
    }

    /// @dev Runs a simulation step and returns the result it reverted with; any other revert is passed on
    function _simulate(bytes memory step) private returns (bytes memory result) {
        (, bytes memory ret) = address(this).call(step);
        if (ret.length >= 4 && bytes4(ret) == SimulationResult.selector) {
            assembly ("memory-safe") {
                let length := mload(ret)
                ret := add(ret, 4)
                mstore(ret, sub(length, 4))
            }
            return abi.decode(ret, (bytes));
        }
        assembly ("memory-safe") {
            revert(add(ret, 32), mload(ret))
        }
    }

    function _prepareMulticurveQuote(CreateParams calldata createData)
        private
        returns (address asset, PoolKey memory poolKey, bool zeroForOne)
    {
        (asset,,,,) = airlock.create(createData);
        (,,,,, poolKey,) = DopplerHookInitializer(payable(address(createData.poolInitializer))).getState(asset);

        address currency0 = Currency.unwrap(poolKey.currency0);
        address currency1 = Currency.unwrap(poolKey.currency1);

        if (asset == currency0) {
            zeroForOne = false;
        } else if (asset == currency1) {
            zeroForOne = true;
        } else {
            revert AssetNotInPool();
        }
    }

    function _resolveExactOutAmount(
        CreateParams calldata createData,
        uint128 overrideAmount
    ) private pure returns (uint128 amount) {
        if (overrideAmount != 0) {
            amount = overrideAmount;
        } else {
            uint256 numTokensToSell = createData.numTokensToSell;
            if (numTokensToSell == 0) revert ExactAmountZero();
            if (numTokensToSell > type(uint128).max) revert ExactAmountTooLarge();
            amount = uint128(numTokensToSell);
        }
    }

    /**
     * @notice Bundles the creation of an asset via the Airlock contract and a buy operation via the Universal Router
     * @dev Only `msg.value` goes to the router, and only what this call left behind goes back to the caller: tokens or
     *      ETH that were already in the Bundler are never spent or refunded (audit ATH-04).
     * @param createData Creation data to pass to the Airlock contract
     * @param commands Encoded commands for the Universal Router
     * @param inputs Encoded inputs for the Universal Router
     */
    function bundle(
        CreateParams calldata createData,
        bytes calldata commands,
        bytes[] calldata inputs
    ) external payable {
        address numeraire = createData.numeraire;
        uint256 ethBefore = address(this).balance - msg.value;
        uint256 numeraireBefore = SafeTransferLib.balanceOf(numeraire, address(this));

        (address asset,,,,) = airlock.create(createData);
        router.execute{ value: msg.value }(commands, inputs);

        uint256 ethBalance = address(this).balance;
        if (ethBalance > ethBefore) SafeTransferLib.safeTransferETH(msg.sender, ethBalance - ethBefore);

        // The asset is created by this call, so all of it that the Bundler holds came from this call.
        uint256 assetBalance = SafeTransferLib.balanceOf(asset, address(this));
        if (assetBalance > 0) SafeTransferLib.safeTransfer(asset, msg.sender, assetBalance);

        uint256 numeraireBalance = SafeTransferLib.balanceOf(numeraire, address(this));
        if (numeraireBalance > numeraireBefore) {
            SafeTransferLib.safeTransfer(numeraire, msg.sender, numeraireBalance - numeraireBefore);
        }
    }
}
