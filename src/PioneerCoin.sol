// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Pioneer Coin (PIO)
 * @author Jozsef Benczedi
 * Collateral: Exogenous (ETH & BTC & SOL)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * 
 * @notice This is the contract meant to be governed by the PioneersEngine.
 * @notice This contract is just the ERC20 implementation of our stable coin system.
 */
contract PioneerCoin is ERC20Burnable, Ownable {
    error PIO__MustBeMoreThanZero();
    error PIO__BurnAmountExeedsBalance();

    // The owner will be the pioneers engine
    constructor() ERC20("Pioneer Coin", "PIO") Ownable(msg.sender) {
    }

    modifier greaterThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert PIO__MustBeMoreThanZero();
        }
        _;
    }

    function mint(address _to, uint256 _amount) external onlyOwner greaterThanZero(_amount) returns(bool) {
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public override onlyOwner greaterThanZero(_amount) {
        uint256 balanceSender = balanceOf(msg.sender);
        if (balanceSender < _amount) {
            revert PIO__BurnAmountExeedsBalance();
        }
        super.burn(_amount);
    }
}
