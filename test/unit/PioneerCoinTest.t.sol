// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PioneerCoin} from "../../src/PioneerCoin.sol";

contract PioneerCoinTest is Test {
    PioneerCoin private pioneerCoin;

    constructor() {
        pioneerCoin = new PioneerCoin();
    }

    // Minting tokens to a valid address by the owner
    function testMintingTokensToValidAddress() public {
        // Arrange
        uint256 mintAmount = 1000;

        // Act
        pioneerCoin.mint(address(this), mintAmount);

        // Assert
        assertEq(pioneerCoin.balanceOf(address(this)), mintAmount);
    }

    // Checking the total supply after minting tokens
    function testTotalSupplyIncreasesAfterMinting() public {
        // Arrange
        uint256 mintAmount = 1000;

        // Act
        pioneerCoin.mint(address(this), mintAmount);

        // Assert
        assertEq(pioneerCoin.totalSupply(), mintAmount);
    }

    // Minting tokens to the zero address
    function testMintingTokenstToZeroAddress() public {
        // Arrange
        address zeroAddress = address(0);
        uint256 mintAmount = 1000;

        // Act and Assert
        vm.expectRevert();
        pioneerCoin.mint(zeroAddress, mintAmount);
    }

    // Minting zero tokens
    function testMintingZeroTokens() public {
        // Arrange
        uint256 mintAmount = 0;

        // Act and Assert
        vm.expectRevert(PioneerCoin.PIO__MustBeMoreThanZero.selector);
        pioneerCoin.mint(address(this), mintAmount);
    }

    // Burning tokens by the owner with sufficient balance
    function testBurningTokensWithSufficientBalance() public {
        // Arrange
        uint256 initialBalance = 1000;
        uint256 burnAmount = 500;
        pioneerCoin.mint(address(this), initialBalance);

        // Act
        vm.prank(pioneerCoin.owner());
        pioneerCoin.burn(burnAmount);

        // Assert
        assertEq(pioneerCoin.balanceOf(address(this)), initialBalance - burnAmount);
        assertEq(pioneerCoin.totalSupply(), 500);
    }

    // Burning tokens with insufficient balance
    function testBurnWithInsufficientBallance() public {
        // Arrange
        uint256 initialBalance = 1000;
        uint256 burnAmount = 1500;
        pioneerCoin.mint(address(this), initialBalance);

        // Act and Assert
        vm.prank(pioneerCoin.owner());
        vm.expectRevert(PioneerCoin.PIO__BurnAmountExeedsBalance.selector);
        pioneerCoin.burn(burnAmount);
        assertEq(pioneerCoin.totalSupply(), initialBalance);
    }

    // Burning zero tokens
    function testBurnZeroTokens() public {
        // Arrange
        uint256 initialBalance = 1000;
        pioneerCoin.mint(address(this), initialBalance);

        // Act and Assert
        vm.prank(pioneerCoin.owner());
        vm.expectRevert(PioneerCoin.PIO__MustBeMoreThanZero.selector);
        pioneerCoin.burn(0);
        assertEq(pioneerCoin.totalSupply(), initialBalance);
    }
}
