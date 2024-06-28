// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {PioneerCoin} from "../src/PioneerCoin.sol";
import {PioEngine} from "../src/PioEngine.sol";
import {PioEngineImpl} from "../src/PioEngineImpl.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPio is Script {
    function run() external returns (PioneerCoin, PioEngineImpl, PioEngine.TokenDetails[] memory) {
        // get the config
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc,) = config.activeNetworkConfig();
        PioEngine.TokenDetails[] memory tokenDetails = new PioEngine.TokenDetails[](2);
        tokenDetails[0] = PioEngine.TokenDetails(PioEngine.CollateralToken.BTC, wbtc, wbtcUsdPriceFeed, true);
        tokenDetails[1] = PioEngine.TokenDetails(PioEngine.CollateralToken.ETH, weth, wethUsdPriceFeed, true);

        // deploy the coin and engine
        vm.startBroadcast();
        PioneerCoin coin = new PioneerCoin();
        PioEngineImpl engine = new PioEngineImpl(tokenDetails, address(coin));
        coin.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (coin, engine, tokenDetails);
    }
}
