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

contract PioEngineTest is Test {
    PioneerCoin private pio;
    PioEngineImpl private engine;
    PioEngine.TokenDetails private btc;
    PioEngine.TokenDetails private eth;
    address weth;

    uint256 private constant STARTING_USER_BALANCE = 10 ether;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;   // 1.0
    uint256 private constant LIQUIDATION_THRESHOLD = 50;

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

    function testDepositCollateralEmmittedEvent() public depositedCollateral {
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
    function testRevertsIfTransferFromFails() public {
        // arrange - create new engine with mock eth that always fails on transfers
        ERC20MockTransferFail mockEth = new ERC20MockTransferFail();
        PioEngine.TokenDetails[] memory collateralTokens = new PioEngine.TokenDetails[](1);
        collateralTokens[0] = PioEngine.TokenDetails(PioEngine.CollateralToken.ETH, address(mockEth), eth.pricefeedAddress, true);
        PioEngineImpl engine2 = new PioEngineImpl(collateralTokens, address(pio));

        // act and assert
        vm.startPrank(bob);
        vm.expectRevert(PioEngineImpl.PIOEngine__TransferFailed.selector);
        engine2.depositCollateral(address(mockEth), STARTING_USER_BALANCE);
        vm.stopPrank();
    }

    // Mint Pio Tests

    // Redeem Collateral Tests

    // Burn Pio Tests

    // Liquidation Tests

    // Health Factor Tests

    // Price Feed Tests

    // Oracle Tests
}
