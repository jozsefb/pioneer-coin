// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.24;

contract PioEngineEvents {
    /** @dev emmited when the user deposits either ETH or BTC */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    /** @dev emmited when the user redeemds either ETH or BTC for PIO */
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);
}
