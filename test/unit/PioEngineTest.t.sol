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

contract PioEngineTest is Test {
    PioneerCoin private pio;
    PioEngineImpl private engine;
    PioEngine.TokenDetails private btc;
    PioEngine.TokenDetails private eth;
    address private weth;

    uint256 private constant STARTING_USER_BALANCE = 10 ether;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;   // 1.0
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MINT_AMOUNT = 5e21; // $5000
    uint256 private constant REDEEM_AMOUNT = 1 ether; // usd/pio value 2e21

    address private bob = makeAddr("Bob");

    function setUp() public {
        DeployPio deployer = new DeployPio();
        PioEngine.TokenDetails[] memory tokenDetails;
        (pio, engine, tokenDetails) = deployer.run();
        btc = tokenDetails[0];
        eth = tokenDetails[1];
        weth = eth.tokenAddress;
        ERC20Mock(weth).mint(bob, 100 ether);
    }

    /**
    *  Deposit Collateral Tests
    */
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

    // Health Factor Tests
    function testHealthFactorIsInfiniteWhenNoPioMinted() public depositedCollateral {
        vm.prank(bob);
        engine.getHealthFactor(bob);
        assertEq(engine.getHealthFactor(bob), type(uint256).max);
    }

    // Mint Pio Tests
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

    // Health factor test 2
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

    // deposit collateral and mint pio tests
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

    // Redeem Collateral Tests
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
        PioEngine.TokenDetails[] memory collateralTokens = new PioEngine.TokenDetails[](1);
        collateralTokens[0] = PioEngine.TokenDetails(PioEngine.CollateralToken.ETH, address(mockEth), eth.pricefeedAddress, true);
        PioEngineImpl engine2 = new PioEngineImpl(collateralTokens, address(pio));
        // transfer ownership of the pio token to the new mocked engine
        vm.prank(address(engine));
        pio.transferOwnership(address(engine2));

        // act and assert
        vm.startPrank(bob);
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

    // Burn Pio Tests

    // Liquidation Tests


    // Price Feed Tests

    // Oracle Tests
}
