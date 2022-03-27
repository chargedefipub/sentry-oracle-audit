// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import './ISentryStrategy.sol';
import './ISanctionsList.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';

/**
 * @title Charge Defi Sentry contract
 * @notice Allows registration of custom contracts to allow actions per address. Contracts can extend this contract and
 		  use the canExecute modifier for functions that need to be restricted
 *
 */
abstract contract Sentry is AccessControlEnumerable {
	// Strategies that can be used to determine to block action;
	ISentryStrategy[] public strategies;

	// Contract that looks up sanctioned wallets provided by Chainanalysis
	ISanctionsList public sanctionsList;

	event AddSentryStrategy(address indexed strategy);
	event RemoveSentryStrategy(address indexed strategy);
	event UpdateSanctionsList(address indexed sanctionsList);

	modifier canExecute(address _address) {
		// if sanctions list is registered, only accounts not on the list can proceed
		if (address(sanctionsList) != address(0)) {
			require(
				!sanctionsList.isSanctioned(_address),
				'Address is sanctioned'
			);
		}

		// accounts that are allowed via sentry strategies can proceed
		for (uint256 i = 0; i < strategies.length; i++) {
			require(strategies[i].isAllowed(_address), 'Blocked by strategy');
		}
		_;
	}

	/**
	 * @notice Adds an address as ISentryStrategy
	 * @param strategy The strategy contract
	 */
	function addSentryStrategy(ISentryStrategy strategy)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(strategies.length <= 10, 'Too many strategies');

		for (uint256 i = 0; i < strategies.length; i++) {
			require(strategies[i] != strategy, 'Strategy exists');
		}
		strategies.push(strategy);

		emit AddSentryStrategy(address(strategy));
	}

	/**
	 * @notice Removes an address as ISentryStrategy
	 * @param strategy The strategy contract
	 */
	function removeSentryStrategy(ISentryStrategy strategy)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		for (uint256 i = 0; i < strategies.length; i++) {
			if (strategies[i] == strategy) {
				strategies[i] = strategies[strategies.length - 1];
				strategies.pop();
				emit RemoveSentryStrategy(address(strategy));
				return;
			}
		}

		revert('Strategy not found');
	}

	/**
	 * @notice Updates the sanctions list
	 * @param _sanctionsList The new sanctions list
	 */
	function updateSanctionsList(ISanctionsList _sanctionsList)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(
			address(sanctionsList) != address(_sanctionsList),
			'Should be a new address'
		);
		sanctionsList = _sanctionsList;
		emit UpdateSanctionsList(address(sanctionsList));
	}
}
