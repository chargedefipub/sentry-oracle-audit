// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface ISentryStrategy {
	function isAllowed(address addr) external view returns (bool);
}
