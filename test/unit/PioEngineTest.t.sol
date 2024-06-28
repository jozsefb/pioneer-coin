// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PioneerCoin} from "../../src/PioneerCoin.sol";
import {PioEngine} from "../../src/PioEngine.sol";
import {PioEngineImpl} from "../../src/PioEngineImpl.sol";
import {DeployPio} from "../../script/DeployPio.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PioEngineTest is Test {
    PioneerCoin private pio;
    PioEngineImpl private engine;
    PioEngine.TokenDetails private btc;
    PioEngine.TokenDetails private eth;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;   // 1.0
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public {
        DeployPio deployer = new DeployPio();
        PioEngine.TokenDetails[] memory tokenDetails;
        (pio, engine, tokenDetails) = deployer.run();
        btc = tokenDetails[0];
        eth = tokenDetails[1];
    }
}
