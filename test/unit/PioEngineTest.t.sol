// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PioneerCoin} from "../../src/PioneerCoin.sol";
import {PioEngine} from "../../src/PioEngine.sol";
import {PioEngineImpl} from "../../src/PioEngineImpl.sol";
import {PioEngineEvents} from "../../src/PioEngineEvents.sol";
import {DeployPio} from "../../script/DeployPio.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC20MockTransferFail} from "../mocks/ERC20MockTransferFail.sol";
import {ERC20MockTransferFromFail} from "../mocks/ERC20MockTransferFromFail.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract PioEngineTest is Test {
    PioneerCoin private pio;
    PioEngineImpl private engine;
    PioEngine.TokenDetails private btc;
    PioEngine.TokenDetails private eth;
    address private weth;

    uint256 private constant ETH_BALANCE = 100 ether;
    uint256 private constant STARTING_USER_BALANCE = 10 ether;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;   // 1.0
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MINT_AMOUNT = 5e21; // $5000
    uint256 private constant REDEEM_AMOUNT = 1 ether; // usd/pio value 2e21

    address private bob = makeAddr("Bob");
    address private alice = makeAddr("Alice");

    function setUp() public {
        DeployPio deployer = new DeployPio();
        PioEngine.TokenDetails[] memory tokenDetails;
        (pio, engine, tokenDetails) = deployer.run();
        btc = tokenDetails[0];
        eth = tokenDetails[1];
        weth = eth.tokenAddress;
        ERC20Mock(weth).mint(bob, ETH_BALANCE);
    }




    ///////////////////////////////////////
    //    Deposit Collateral Tests    /////
    ///////////////////////////////////////
    function testDepositRevertOnZeroCollateral() public {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(pio), 1 ether);

        vm.expectRevert(PioEngineImpl.PIOEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositRevertsWithUnApprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(address(this), STARTING_USER_BALANCE);

        vm.startPrank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__InvalidToken.selector);
        engine.depositCollateral(address(ranToken), 1 ether);
        vm.stopPrank();
    }

    function testDepositCollateralEmmitsEvent() public depositedCollateral {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), STARTING_USER_BALANCE);
        vm.expectEmit(true, true, true, false, address(engine));
        emit PioEngineEvents.CollateralDeposited(bob, weth, STARTING_USER_BALANCE);
        engine.depositCollateral(weth, STARTING_USER_BALANCE);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), STARTING_USER_BALANCE);
        engine.depositCollateral(weth, STARTING_USER_BALANCE);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalPioMinted, uint256 totalCollateralUsdValue) = engine.getAccountInformation(bob);
        assertEq(totalPioMinted, 0);
        assertEq(totalCollateralUsdValue, 20000e18); // 10 eth = $20.000
    }

    // this test needs it's own setup
    function testDepositCollateralRevertsIfTransferFromFails() public {
        // arrange - create new engine with mock eth that always fails on transfers
        ERC20MockTransferFromFail mockEth = new ERC20MockTransferFromFail();
        PioEngine.TokenDetails[] memory collateralTokens = new PioEngine.TokenDetails[](1);
        collateralTokens[0] = PioEngine.TokenDetails(PioEngine.CollateralToken.ETH, address(mockEth), eth.pricefeedAddress, true);
        PioEngineImpl engine2 = new PioEngineImpl(collateralTokens, address(pio));

        // act and assert
        vm.startPrank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__TransferFailed.selector);
        engine2.depositCollateral(address(mockEth), STARTING_USER_BALANCE);
        vm.stopPrank();
    }





    /////////////////////////////////
    //    Health Factor Tests    ////
    /////////////////////////////////
    function testHealthFactorIsInfiniteWhenNoPioMinted() public depositedCollateral {
        vm.prank(bob);
        engine.getHealthFactor(bob);
        assertEq(engine.getHealthFactor(bob), type(uint256).max);
    }

    function testHealthFactorIsReportedCorrectly() public depositedCollateral pioMinted {
        // arrange
        uint256 initialHealthFactor = engine.getHealthFactor(bob);
        vm.prank(bob);
        // act
        engine.mintPio(MINT_AMOUNT); // doubling the minted amount
        // assert
        uint256 newHealthFactor = engine.getHealthFactor(bob);
        assertTrue(initialHealthFactor > 0);
        assertTrue(newHealthFactor < initialHealthFactor);
        assertEq(newHealthFactor, initialHealthFactor / 2);
    }




    ////////////////////////////
    //    Mint Pio Tests    ////
    ////////////////////////////
    function testMintPioZeroAmount() public depositedCollateral {
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__MustBeMoreThanZero.selector);
        engine.mintPio(0);
    }

    function testMintPioRevertsIfHealthFactorBroken() public depositedCollateral {
        uint256 amountToMint = 20000e18; // 1eth = 2000$ = 2000 pio. deposit is 10 ether. health factor will break when trying to mint deposit size amount.
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__BreaksHealthFactor.selector);
        engine.mintPio(amountToMint);
    }

    modifier pioMinted() {
        vm.startPrank(bob);
        engine.mintPio(MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testMintPioIncreasesTotalSupply() public depositedCollateral pioMinted {
        uint256 totalSupply = pio.totalSupply();
        assertEq(totalSupply, MINT_AMOUNT);
    }





    ///////////////////////////////////////////////////
    //    deposit collateral and mint pio tests    ////
    ///////////////////////////////////////////////////
    function testDepositCollateralAndMintPioRevertsIfZeroAmountCollateral() public depositedCollateral {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), STARTING_USER_BALANCE);
        vm.expectRevert(PioEngineImpl.PIOEngine__MustBeMoreThanZero.selector);
        engine.depositCollateralAndMintPio(weth, 0, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintPioRevertsIfZeroAmountToMint() public depositedCollateral {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), STARTING_USER_BALANCE);
        vm.expectRevert(PioEngineImpl.PIOEngine__MustBeMoreThanZero.selector);
        engine.depositCollateralAndMintPio(weth, STARTING_USER_BALANCE, 0);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintPioRevertsIfInvalidCollateral() public depositedCollateral {
        ERC20Mock mockToken = new ERC20Mock();
        vm.startPrank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__InvalidToken.selector);
        engine.depositCollateralAndMintPio(address(mockToken), STARTING_USER_BALANCE, MINT_AMOUNT);
        vm.stopPrank();
    }

    modifier depositedCollateralAndPioMinted() {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), STARTING_USER_BALANCE);
        engine.depositCollateralAndMintPio(weth, STARTING_USER_BALANCE, MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndMintPio() public depositedCollateralAndPioMinted {
        uint256 pioAmount = pio.balanceOf(bob);
        assertEq(pioAmount, MINT_AMOUNT);
        (, uint256 totalCollateralUsdValue) = engine.getAccountInformation(bob);
        assertEq(totalCollateralUsdValue, 20e21);
    }





    /////////////////////////////////////
    //    Redeem Collateral Tests    ////
    /////////////////////////////////////
    function testRedeemCollateralRevertsIfZeroAmount() public depositedCollateralAndPioMinted {
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralRevertsIfRedeemingWrongToken() public depositedCollateralAndPioMinted {
        ERC20Mock newMockedToken = new ERC20Mock();
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__InvalidToken.selector);
        engine.redeemCollateral(address(newMockedToken), MINT_AMOUNT);
    }

    function testRedeemCollateralRevertsIfNotEnoughCollateral() public depositedCollateralAndPioMinted {
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PioEngine__NotEnoughCollateral.selector);
        engine.redeemCollateral(btc.tokenAddress, MINT_AMOUNT);
    }

    function testRedeemCollateralRevertsIfHealthFactorBroken() public depositedCollateralAndPioMinted {
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__BreaksHealthFactor.selector);
        engine.redeemCollateral(weth, STARTING_USER_BALANCE);
    }

    // this test needs it's own setup
    function testRedeemCollateralRevertsIfTransferFails() public {
        // arrange - create new engine with mock eth that always fails on transfers
        ERC20MockTransferFail mockEth = new ERC20MockTransferFail();
        mockEth.mint(bob, STARTING_USER_BALANCE);
        PioEngine.TokenDetails[] memory collateralTokens = new PioEngine.TokenDetails[](1);
        collateralTokens[0] = PioEngine.TokenDetails(PioEngine.CollateralToken.ETH, address(mockEth), eth.pricefeedAddress, true);
        PioEngineImpl engine2 = new PioEngineImpl(collateralTokens, address(pio));
        // transfer ownership of the pio token to the new mocked engine
        vm.prank(address(engine));
        pio.transferOwnership(address(engine2));

        // act and assert
        vm.startPrank(bob);
        mockEth.approve(address(engine2), STARTING_USER_BALANCE);
        engine2.depositCollateralAndMintPio(address(mockEth), STARTING_USER_BALANCE, MINT_AMOUNT);
        vm.expectRevert(PioEngineImpl.PIOEngine__TransferFailed.selector);
        engine2.redeemCollateral(address(mockEth), 1e18);
        vm.stopPrank();
    }

    function testRedeemCollateralEmitsEvent() public depositedCollateralAndPioMinted {
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, false, address(engine));
        emit PioEngineEvents.CollateralRedeemed(bob, bob, weth, REDEEM_AMOUNT);
        engine.redeemCollateral(weth, REDEEM_AMOUNT);
        vm.stopPrank();
    }

    function testRedeemCollateralSuccess() public depositedCollateralAndPioMinted {
        uint256 totalCollateralUsdValue = engine.getAccountCollateralValue(bob);
        vm.prank(bob);
        engine.redeemCollateral(weth, REDEEM_AMOUNT);
        uint256 newTotalCollateralUsdValue = engine.getAccountCollateralValue(bob);
        assertEq(newTotalCollateralUsdValue, totalCollateralUsdValue - 2e21);
    }

    function testRedeemingCollateralLowersHealthFactor() public depositedCollateralAndPioMinted {
        uint256 initialHealthFactor = engine.getHealthFactor(bob);
        vm.prank(bob);
        engine.redeemCollateral(weth, REDEEM_AMOUNT);
        uint256 newHealthFactor = engine.getHealthFactor(bob);
        assertTrue(newHealthFactor < initialHealthFactor);
    }





    ////////////////////////////
    //    Burn Pio Tests    ////
    ////////////////////////////
    function testBurnRevertsIfZeroAmount() public depositedCollateralAndPioMinted {
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__MustBeMoreThanZero.selector);
        engine.burn(0);
    }

    function testBurnRevertsIfNotEnoughPio() public depositedCollateralAndPioMinted {
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PioEngine__NotEnoughPio.selector);
        engine.burn(MINT_AMOUNT + 1);
    }

    function testBurnSuccess() public depositedCollateralAndPioMinted {
        vm.startPrank(bob);
        pio.approve(address(engine), 1e21);
        engine.burn(1e21);
        vm.stopPrank();
        assertEq(pio.balanceOf(bob), 4e21);
    }






    //////////////////////////////////////////////////
    //    Redeem Collateral and Burn Pio Tests    ////
    //////////////////////////////////////////////////
    function testRedeemCollateralAndBurnRevertsIfZeroAmountCollateral() public depositedCollateralAndPioMinted {
        vm.startPrank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateralAndBurnPio(weth, 0, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testRedeemCollateralAndBurnRevertsIfZeroAmountToBurn() public depositedCollateralAndPioMinted {
        vm.startPrank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateralAndBurnPio(weth, 1 ether, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralAndBurnRevertsIfInvalidCollateral() public depositedCollateralAndPioMinted {
        ERC20Mock newMockedToken = new ERC20Mock();
        vm.startPrank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__InvalidToken.selector);
        engine.redeemCollateralAndBurnPio(address(newMockedToken), 1 ether, 1 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralAndBurnPioSuccess() public depositedCollateralAndPioMinted {
        (uint256 pioAmount, uint256 totalCollateralUsdValue) = engine.getAccountInformation(bob);
        uint256 burnAmount = 2e21;
        uint256 expectedPioAmount = pioAmount - burnAmount;
        uint256 expectedCollateralAmount = totalCollateralUsdValue - REDEEM_AMOUNT * 2000;
        vm.startPrank(bob);
        pio.approve(address(engine), burnAmount);
        engine.redeemCollateralAndBurnPio(weth, REDEEM_AMOUNT, burnAmount); // burns same amount as redeems
        vm.stopPrank();
        (uint256 newPioAmount, uint256 newTotalCollateralUsdValue) = engine.getAccountInformation(bob);
        assertEq(newPioAmount, expectedPioAmount);
        assertEq(newTotalCollateralUsdValue, expectedCollateralAmount);
    }





    //////////////////////////////
    //    Price Feed Tests    ////
    //////////////////////////////
    function testGetTokenAmountFromUSDValueReturnsTheCorrectValue() public view {
        uint256 usdValue = 2000e18; // $2k represented with 18 decimals
        uint256 expectedCollateralAmount = 1 ether; // 1 eth = $2k
        uint256 result = engine.getTokenAmountFromUSDValue(weth, usdValue);
        assertEq(expectedCollateralAmount, result); 
    }

    function testGetUsdValueReturnsTheCorrectValue() public view {
        uint256 expectedUsdValue = 2000e18; // $2k represented with 18 decimals
        uint256 result = engine.getUsdValue(weth, 1 ether);
        assertEq(expectedUsdValue, result);
    }

    function testGetAccountCollateralValueReturnsTheCorrectValue() public depositedCollateral {
        vm.startPrank(bob);
        ERC20Mock(btc.tokenAddress).mint(bob, STARTING_USER_BALANCE);
        ERC20Mock(btc.tokenAddress).approve(address(engine), STARTING_USER_BALANCE);
        engine.depositCollateral(btc.tokenAddress, 1 ether);
        vm.stopPrank();
        uint256 expectedUsdValue = 70000e18; // $50k from btc + $20k from eth
        uint256 result = engine.getAccountCollateralValue(bob);
        assertEq(expectedUsdValue, result);
    }




    /////////////////////////////////
    //    Liquidation Tests    //////
    /////////////////////////////////
    function testLiquidateRevertsIfZeroAmount() public depositedCollateralAndPioMinted {
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__MustBeMoreThanZero.selector);
        engine.liquidate(weth, alice, 0);
    }

    modifier aliceMintedPio() {
        ERC20Mock(weth).mint(alice, ETH_BALANCE);
        vm.startPrank(alice);
        ERC20Mock(weth).approve(address(engine), STARTING_USER_BALANCE);
        engine.depositCollateralAndMintPio(weth, 1 ether, 1000e18); // alice mints for the max collateral value (1/5 of Bob)
        vm.stopPrank();
        _;
    }

    function testLiquidationRevertsIfHealthFactorAboveThreshold() public depositedCollateralAndPioMinted aliceMintedPio {
        vm.prank(bob);
        vm.expectRevert(PioEngineImpl.PioEngine__HealthfactorOK.selector);
        engine.liquidate(weth, alice, 1 ether);
    }

    modifier ethPriceDrops() {
        MockV3Aggregator(eth.pricefeedAddress).updateAnswer(1500e8); // $1.5k
        _;
    }

    // not enough collateral to give to the user that's making the liquidation
    // cannot liquidate a higher amount than the debt to cover

    function testLiquidateRevertsIfInvalidCollateral() public depositedCollateralAndPioMinted aliceMintedPio ethPriceDrops {
        address newToken = address(new ERC20Mock());
        vm.startPrank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__InvalidToken.selector);
        engine.liquidate(newToken, alice, 1 ether);
        vm.stopPrank();
    }

    // liquidate 100 PIO and request btc -> this is too much because alice only deposited eth
    function testLiquidateRevertsIfInsufficientCollateral() public depositedCollateralAndPioMinted aliceMintedPio ethPriceDrops {
        vm.startPrank(bob);
        vm.expectRevert();
        engine.liquidate(btc.tokenAddress, alice, 100e18);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfAmountLargerThanDebtToCover() public depositedCollateralAndPioMinted aliceMintedPio ethPriceDrops {
        vm.startPrank(bob);
        vm.expectRevert(PioEngineImpl.PioEngine__NotEnoughPio.selector);
        engine.liquidate(eth.tokenAddress, alice, 1001e18); // alice minted 1000 pio
        vm.stopPrank();
    }

    /**
    ETH_USD_PRICE = 2000e8
    LIQUIDATION_THRESHOLD = 50% (0.5)
    Alice: deposit: 1 eth ($2000), mint $1000 PIO -> health factor (1.0)

    ETH_USD_PRICE = 1000e8
    Alice account: 1 eth ($1000), $1000 PIO -> health factor (0.5)

    Bob liquidates: $100 PIO -> 
    1. Alice: 1 eth, $900 PIO
    2. Alice: 1 eth - ($100 + $10) -> 0.89 eth ($890)
    3. Alice: 0.89 eth ($890), $900 PIO -> health factor -> health factor (0.494)
    */
    function testLiquidateReversIfHealthFactorNotImproved() public depositedCollateralAndPioMinted aliceMintedPio {
        MockV3Aggregator(eth.pricefeedAddress).updateAnswer(1000e8); // $1k
        uint256 amountToLiquidate = 100e18;
        vm.startPrank(bob);
        pio.approve(address(engine), amountToLiquidate);
        vm.expectRevert(PioEngineImpl.PioEngine__HealthfactorNotImproved.selector);
        engine.liquidate(eth.tokenAddress, alice, amountToLiquidate); // alice minted 1000 pio
        vm.stopPrank();
    }

    /**
    ETH_USD_PRICE = 2000e8
    LIQUIDATION_THRESHOLD = 50% (0.5)
    Alice: deposit: 1 eth ($2000), mint $1000 PIO -> health factor (1.0)

    ETH_USD_PRICE = 1500e8
    Alice account: 1 eth ($1500), $1000 PIO -> health factor (0.75)

    Bob liquidates: $500 PIO -> 
    1. Alice: 1 eth, $500 PIO
    2. Alice: 1 eth ($1500) - ($500 + $50) -> 0.63 eth ($950)
    3. Alice: 0.63 eth ($950), $500 PIO -> health factor -> health factor (0.95)
    */
    function testLiquidateImprovesHealthFactor() public depositedCollateralAndPioMinted aliceMintedPio ethPriceDrops {
        uint256 initialHealthFactor = engine.getHealthFactor(alice);
        uint256 amountToLiquidate = 500e18;
        vm.startPrank(bob);
        pio.approve(address(engine), amountToLiquidate);
        engine.liquidate(eth.tokenAddress, alice, amountToLiquidate); // alice minted 1000 pio
        vm.stopPrank();
        uint256 newHealthFactor = engine.getHealthFactor(alice);
        assertTrue(newHealthFactor > initialHealthFactor);
    }

    function testLiquidateDecreasesCollateralOfLiquidee() public depositedCollateralAndPioMinted aliceMintedPio ethPriceDrops {
        uint256 amountToLiquidate = 500e18;
        vm.startPrank(bob);
        pio.approve(address(engine), amountToLiquidate);
        engine.liquidate(eth.tokenAddress, alice, amountToLiquidate); // alice minted 1000 pio
        vm.stopPrank();
        uint256 aliceEthBalance = ERC20Mock(weth).balanceOf(alice);
        assertTrue(aliceEthBalance < ETH_BALANCE);
    }

    function testLiquidateGives10PercentBonusCollateral() public depositedCollateralAndPioMinted aliceMintedPio ethPriceDrops {
        uint256 amountToLiquidate = 1000e18;
        vm.startPrank(bob);
        pio.approve(address(engine), amountToLiquidate);
        engine.liquidate(eth.tokenAddress, alice, amountToLiquidate); // alice minted 1000 pio
        vm.stopPrank();
        uint256 bobEthBalance = ERC20Mock(weth).balanceOf(bob);
        uint256 expecetedCollateral = (amountToLiquidate + amountToLiquidate / 10) / 1500;
        uint256 expectedBalance = ETH_BALANCE - STARTING_USER_BALANCE + expecetedCollateral;
        assertTrue(expectedBalance - bobEthBalance <= 1);
    }

    //bob health factor < 1 -> liquidate alice -> revert
    function testLiqudateRevertsIfUserHealthFactorBroken() public depositedCollateralAndPioMinted aliceMintedPio {
        vm.startPrank(bob);
        engine.redeemCollateral(weth, 5 ether); // redeem collateral -> bob health factor == alice helath factor == 1
        vm.stopPrank();
        MockV3Aggregator(eth.pricefeedAddress).updateAnswer(1500e8); // bob hf = alice hf = 0.5
        uint256 amountToLiquidate = 500e18;
        vm.startPrank(bob);
        pio.approve(address(engine), amountToLiquidate);
        vm.expectRevert(PioEngineImpl.PIOEngine__BreaksHealthFactor.selector);
        engine.liquidate(eth.tokenAddress, alice, amountToLiquidate);
        vm.stopPrank();
    }
}
