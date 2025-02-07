// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2020 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.6;
pragma experimental ABIEncoderV2;

import "./interfaces/ICurve.sol";
import "./ApproximateBuys.sol";
import "./SamplerUtils.sol";


contract CurveSampler is
    SamplerUtils,
    ApproximateBuys
{
    /// @dev Information for sampling from curve sources.
    struct CurveInfo {
        address poolAddress;
        bytes4 sellQuoteFunctionSelector;
        bytes4 buyQuoteFunctionSelector;
    }

    /// @dev Base gas limit for Curve calls. Some Curves have multiple tokens
    ///      So a reasonable ceil is 150k per token. Biggest Curve has 4 tokens.
    uint256 constant private CURVE_CALL_GAS = 2000e3; // Was 600k for Curve but SnowSwap is using 1500k+

    /// @dev Sample sell quotes from Curve.
    /// @param curveInfo Curve information specific to this token pair.
    /// @param fromTokenIdx Index of the taker token (what to sell).
    /// @param toTokenIdx Index of the maker token (what to buy).
    /// @param takerTokenAmounts Taker token sell amount for each sample.
    /// @return makerTokenAmounts Maker amounts bought at each taker token
    ///         amount.
    function sampleSellsFromCurve(
        CurveInfo memory curveInfo,
        int128 fromTokenIdx,
        int128 toTokenIdx,
        uint256[] memory takerTokenAmounts
    )
        public
        view
        returns (uint256[] memory makerTokenAmounts)
    {
        uint256 numSamples = takerTokenAmounts.length;
        makerTokenAmounts = new uint256[](numSamples);
        for (uint256 i = 0; i < numSamples; i++) {
            (bool didSucceed, bytes memory resultData) =
                curveInfo.poolAddress.staticcall.gas(CURVE_CALL_GAS)(
                    abi.encodeWithSelector(
                        curveInfo.sellQuoteFunctionSelector,
                        fromTokenIdx,
                        toTokenIdx,
                        takerTokenAmounts[i]
                    ));
            uint256 buyAmount = 0;
            if (didSucceed) {
                buyAmount = abi.decode(resultData, (uint256));
            }
            makerTokenAmounts[i] = buyAmount;
            // Break early if there are 0 amounts
            if (makerTokenAmounts[i] == 0) {
                break;
            }
        }
    }

    /// @dev Sample buy quotes from Curve.
    /// @param curveInfo Curve information specific to this token pair.
    /// @param fromTokenIdx Index of the taker token (what to sell).
    /// @param toTokenIdx Index of the maker token (what to buy).
    /// @param makerTokenAmounts Maker token buy amount for each sample.
    /// @return takerTokenAmounts Taker amounts sold at each maker token
    ///         amount.
    function sampleBuysFromCurve(
        CurveInfo memory curveInfo,
        int128 fromTokenIdx,
        int128 toTokenIdx,
        uint256[] memory makerTokenAmounts
    )
        public
        view
        returns (uint256[] memory takerTokenAmounts)
    {
        if (curveInfo.buyQuoteFunctionSelector == bytes4(0)) {
            // Buys not supported on this curve, so approximate it.
            return _sampleApproximateBuys(
                ApproximateBuyQuoteOpts({
                    makerTokenData: abi.encode(toTokenIdx, curveInfo),
                    takerTokenData: abi.encode(fromTokenIdx, curveInfo),
                    getSellQuoteCallback: _sampleSellForApproximateBuyFromCurve
                }),
                makerTokenAmounts
            );
        }
        uint256 numSamples = makerTokenAmounts.length;
        takerTokenAmounts = new uint256[](numSamples);
        for (uint256 i = 0; i < numSamples; i++) {
            (bool didSucceed, bytes memory resultData) =
                curveInfo.poolAddress.staticcall.gas(CURVE_CALL_GAS)(
                    abi.encodeWithSelector(
                        curveInfo.buyQuoteFunctionSelector,
                        fromTokenIdx,
                        toTokenIdx,
                        makerTokenAmounts[i]
                    ));
            uint256 sellAmount = 0;
            if (didSucceed) {
                sellAmount = abi.decode(resultData, (uint256));
            }
            takerTokenAmounts[i] = sellAmount;
            // Break early if there are 0 amounts
            if (takerTokenAmounts[i] == 0) {
                break;
            }
        }
    }

    function _sampleSellForApproximateBuyFromCurve(
        bytes memory takerTokenData,
        bytes memory makerTokenData,
        uint256 sellAmount
    )
        private
        view
        returns (uint256 buyAmount)
    {
        (int128 takerTokenIdx, CurveInfo memory curveInfo) =
            abi.decode(takerTokenData, (int128, CurveInfo));
        (int128 makerTokenIdx) =
            abi.decode(makerTokenData, (int128));
        (bool success, bytes memory resultData) =
            address(this).staticcall(abi.encodeWithSelector(
                this.sampleSellsFromCurve.selector,
                curveInfo,
                takerTokenIdx,
                makerTokenIdx,
                _toSingleValueArray(sellAmount)
            ));
        if (!success) {
            return 0;
        }

        return abi.decode(resultData, (uint256[]))[0];
    }
}
