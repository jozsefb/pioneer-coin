// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract OracleLibTest is StdCheats, Test {
    using OracleLib for AggregatorV3Interface;
    MockV3Aggregator private aggregator;

    function setUp() public {
        aggregator = new MockV3Aggregator(8, 2000e18);
    }

    function testStalePriceCheckRevertsOnTimeout() public {
        vm.warp(block.timestamp + OracleLib.TIMEOUT + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).stalePriceCheck();
    }

    function testStalePriceCheckRevertsOnBadData() public {
        aggregator.updateRoundData(11, 2000e18, 0, 0);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).stalePriceCheck();
    }

    function testStalePriceCheckReturnsPriceFeed() public view {
        (, int256 answer, , , ) = AggregatorV3Interface(address(aggregator)).stalePriceCheck();
        assertEq(2000e18, answer);
    }
}
