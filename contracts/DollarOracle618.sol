// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import './lib/Babylonian.sol';
import './lib/FixedPoint.sol';
import './lib/UniswapV2OracleLibrary.sol';
import './Epoch.sol';
import './Interfaces/IUniswapV2Pair.sol';
import './Interfaces/IUniswapV2Factory.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
// price is always returned as 18 decimals!
// This oracle accepts token pairs where one is 6 decimals and other is 18
contract DollarOracle618 is Epoch {
	using FixedPoint for *;

	/* ========== STATE VARIABLES ========== */

	// uniswap
	address public token0;
	address public token1;
	IUniswapV2Pair public pair;
	uint256 public immutable token0PriceMultiplier;
	uint256 public immutable token1PriceMultiplier;

	// oracle
	uint32 public blockTimestampLast;
	uint256 public price0CumulativeLast;
	uint256 public price1CumulativeLast;
	FixedPoint.uq112x112 public price0Average;
	FixedPoint.uq112x112 public price1Average;

	event Updated(uint256 price0CumulativeLast, uint256 price1CumulativeLast);

	/* ========== CONSTRUCTOR ========== */

	constructor(
		IUniswapV2Pair _pair,
		uint256 _period,
		uint256 _startTime
	) Epoch(_period, _startTime, 0) {
		pair = _pair;
		token0 = pair.token0();
		token1 = pair.token1();
		price0CumulativeLast = pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
		price1CumulativeLast = pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
		uint112 reserve0;
		uint112 reserve1;
		(reserve0, reserve1, blockTimestampLast) = pair.getReserves();
		require(reserve0 != 0 && reserve1 != 0, 'Oracle: NO_RESERVES'); // ensure that there's liquidity in the pair
		require(
			IERC20Metadata(token0).decimals() == 18 ||
				IERC20Metadata(token1).decimals() == 18,
			'One token must be 18 decimals'
		);
		require(
			IERC20Metadata(token0).decimals() == 6 ||
				IERC20Metadata(token1).decimals() == 6,
			'One token must be 6 decimals'
		);
		// since amountOut for tokens will be based off the paired liquidity token, we should use the decimals from the pairing token
		// to compute the price multiplier
		token0PriceMultiplier = uint256(
			10**(uint256(18) - (IERC20Metadata(token1).decimals()))
		);
		token1PriceMultiplier = uint256(
			10**(uint256(18) - (IERC20Metadata(token0).decimals()))
		);
	}

	/* ========== MUTABLE FUNCTIONS ========== */

	/** @dev Updates 1 period EMA price from Uniswap.  */
	function update() external checkEpoch {
		(
			uint256 price0Cumulative,
			uint256 price1Cumulative,
			uint32 blockTimestamp
		) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
		uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

		if (timeElapsed == 0) {
			// prevent divided by zero
			return;
		}

		// overflow is desired, casting never truncates
		// cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
		price0Average = FixedPoint.uq112x112(
			uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
		);
		price1Average = FixedPoint.uq112x112(
			uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
		);

		price0CumulativeLast = price0Cumulative;
		price1CumulativeLast = price1Cumulative;
		blockTimestampLast = blockTimestamp;

		emit Updated(price0Cumulative, price1Cumulative);
	}

	// note this will always return 0 before update has been called successfully for the first time.
	// this always returns prices in 18 decimals
	function consult(address _token, uint256 _amountIn)
		external
		view
		returns (uint256 amountOut)
	{
		if (_token == token0) {
			amountOut =
				uint256(price0Average.mul(_amountIn).decode144()) *
				token0PriceMultiplier;
		} else {
			require(_token == token1, 'Oracle: INVALID_TOKEN');
			amountOut =
				uint256(price1Average.mul(_amountIn).decode144()) *
				token1PriceMultiplier;
		}
	}

	// note this always returns prices in 18 decimals
	function twap(address _token, uint256 _amountIn)
		external
		view
		returns (uint256 _amountOut)
	{
		(
			uint256 price0Cumulative,
			uint256 price1Cumulative,
			uint32 blockTimestamp
		) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
		uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
		if (_token == token0) {
			_amountOut =
				uint256(
					FixedPoint
						.uq112x112(
							uint224(
								(price0Cumulative - price0CumulativeLast) /
									timeElapsed
							)
						)
						.mul(_amountIn)
						.decode144()
				) *
				token0PriceMultiplier;
		} else {
			require(_token == token1, 'Oracle: INVALID_TOKEN');
			_amountOut =
				uint256(
					FixedPoint
						.uq112x112(
							uint224(
								(price1Cumulative - price1CumulativeLast) /
									timeElapsed
							)
						)
						.mul(_amountIn)
						.decode144()
				) *
				token1PriceMultiplier;
		}
	}
}
