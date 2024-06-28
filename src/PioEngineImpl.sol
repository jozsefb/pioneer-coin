// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.24;

import {PioEngine} from "./PioEngine.sol";
import {PioneerCoin} from "./PioneerCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PioEngineImpl is PioEngine, ReentrancyGuard {
    ///////////////
    // ERRORS    //
    /////////////// 
    error PIOEngine__MustBeMoreThanZero();
    error PIOEngine__InvalidToken();

    ///////////////
    // TYPES     //
    ///////////////
    //using OracleLib for AggregatorV3Interface;
 
    //////////////////////
    // STATE VARIABLES  //
    //////////////////////
    uint256 private constant ADDITIONAL_PRICE_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_pioMinted;
    mapping(address token => PioEngine.TokenDetails tokenDetails) private s_priceFeeds;

    PioneerCoin private immutable i_pio;

    ///////////////
    // EVENTS    //
    /////////////// 
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    ///////////////
    // MODIFIERS //
    ///////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert PIOEngine__MustBeMoreThanZero();
        }
        _;
    }
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token].exists == false) {
            revert PIOEngine__InvalidToken();
        }
        _;
    }

    ///////////////
    // FUNCTIONS //
    ///////////////
    constructor(PioEngine.TokenDetails[] memory collateralTokens, address pioAddress) {
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            s_priceFeeds[collateralTokens[i].tokenAddress] = collateralTokens[i];
        }
        i_pio = PioneerCoin(pioAddress);
    }

    ////////////////////////
    // EXTERNAL FUNCTIONS //
    ////////////////////////
    function depositCollateralAndMintPio(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToMint) override external {
    }

    function redeemCollateralForPio(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBurn) override external {
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) override external moreThanZero(amountCollateral) nonReentrant {
    }

    function burn(uint256 amount) override external moreThanZero(amount) nonReentrant {
    }

    function liquidate(address collateral, address user, uint256 debtToCover) override external moreThanZero(debtToCover) nonReentrant {
    }

    ////////////////////////
    // PUBLIC FUNCTIONS //
    ////////////////////////

}
