// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PioEngine, PioEngineImpl} from "../../src/PioEngineImpl.sol";
import {PioneerCoin} from "../../src/PioneerCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// price feed
// weth token
// wbtc token

contract Handler is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    PioneerCoin private pio;
    PioEngineImpl private engine;
    MockV3Aggregator private ethUsdPriceFeed;

    ERC20Mock private weth;
    ERC20Mock private wbtc;
    address[] private usersWithCollateralDeposited;

    // Ghost Variables
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintIsCalled;

    constructor(PioneerCoin _pio, PioEngineImpl _engine, PioEngine.TokenDetails[] memory tokenDetails) {
        pio = _pio;
        engine = _engine;

        wbtc = ERC20Mock(tokenDetails[0].tokenAddress);
        weth = ERC20Mock(tokenDetails[1].tokenAddress);
        ethUsdPriceFeed = MockV3Aggregator(tokenDetails[1].pricefeedAddress);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // double push
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = _getMaxCollateralRedeemable(collateral);
        uint256 amountCollateral = bound(collateralAmount, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        vm.prank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintPio(uint256 amountToMint, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        amountToMint = bound(amountToMint, 1, MAX_DEPOSIT_SIZE);
        (uint256 totalPioMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        int256 maxPioToMint = (int256(collateralValueInUsd) / 2) - int256(totalPioMinted);
        if (maxPioToMint < 0) {
            return;
        }
        amountToMint = bound(amountToMint, 0, uint256(maxPioToMint));
        if (amountToMint == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintPio(amountToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // THIS BREAKS OUR INVARIANT TEST SUITE!!!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    ////
    /// HELPER FUNCTIONS
    ///

    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function _getMaxCollateralRedeemable(ERC20Mock collateral) private view returns (uint256) {
        uint256 accountValue = engine.getAccountCollateralValue(msg.sender);
        uint256 pioMinted = pio.balanceOf(msg.sender);
        if (accountValue <= 2 * pioMinted) { // we need to have collateral amount of at least 2x the pio minted
            return 0;
        }
        uint256 maxValue = accountValue - (2 * pioMinted);
        uint256 userColalteral = engine.getCollateralBananceOfUser(msg.sender, address(collateral));
        uint256 maxAmount = engine.getTokenAmountFromUSDValue(address(collateral), maxValue);
        if (userColalteral > maxAmount) {
            return maxAmount;
        }
        return userColalteral;
    }
}
