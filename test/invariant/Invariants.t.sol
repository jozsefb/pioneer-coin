// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PioneerCoin} from "../../src/PioneerCoin.sol";
import {PioEngine, PioEngineImpl} from "../../src/PioEngineImpl.sol";
import {DeployPio} from "../../script/DeployPio.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariants is StdInvariant, Test{
    PioEngineImpl private engine;
    PioneerCoin private pio;
    DeployPio deployer;
    address weth;
    address wbtc;
    address user = makeAddr("user");
    Handler handler;

    function setUp() public {
        PioEngine.TokenDetails[] memory tokenDetails;
        deployer = new DeployPio();
        (pio, engine, tokenDetails) = deployer.run();
        wbtc = tokenDetails[0].tokenAddress;
        weth = tokenDetails[1].tokenAddress;
        handler = new Handler(pio, engine, tokenDetails);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralThanTotalSupply() public view {
        uint256 totalSupply = pio.totalSupply();
        uint256 totalWeth = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtc = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWeth);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtc);

        console.log("wethValue: ", wethValue);
        console.log("wbtcValue: ", wbtcValue);
        console.log("totalSupply: ", totalSupply);
        console.log("times mint is called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        engine.getAccountInformation(user);
        engine.getAccountCollateralValue(user);
        engine.getUsdValue(weth, 1e18);
        engine.getTokenAmountFromUSDValue(weth, 1e18);
        engine.getHealthFactor(user);
        engine.getCollateralBananceOfUser(user, weth);
    }
}
