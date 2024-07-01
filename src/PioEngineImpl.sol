// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.24;

import {PioEngine} from "./PioEngine.sol";
import {PioEngineEvents} from "./PioEngineEvents.sol";
import {PioneerCoin} from "./PioneerCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";

contract PioEngineImpl is PioEngine, PioEngineEvents, ReentrancyGuard {
    ///////////////
    // ERRORS    //
    /////////////// 
    error PIOEngine__MustBeMoreThanZero();
    error PIOEngine__InvalidToken();
    error PIOEngine__TransferFailed();
    error PIOEngine__MintFailed();
    error PIOEngine__BreaksHealthFactor();
    error PioEngine__NotEnoughCollateral();
    error PioEngine__NotEnoughPio();

    ///////////////
    // TYPES     //
    ///////////////
    using OracleLib for AggregatorV3Interface;
 
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
    mapping(address token => address priceFeedAddress) private s_priceFeeds;
    TokenDetails[] private s_collateralTokens;

    PioneerCoin private immutable i_pio;

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
        if (s_priceFeeds[token] == address(0)) {
            revert PIOEngine__InvalidToken();
        }
        _;
    }

    ///////////////
    // FUNCTIONS //
    ///////////////
    constructor(PioEngine.TokenDetails[] memory collateralTokens, address pioAddress) {
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            s_collateralTokens.push(collateralTokens[i]);
            s_priceFeeds[collateralTokens[i].tokenAddress] = collateralTokens[i].pricefeedAddress;
        }
        i_pio = PioneerCoin(pioAddress);
    }

    ////////////////////////
    // EXTERNAL FUNCTIONS //
    ////////////////////////
    function depositCollateralAndMintPio(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToMint) override 
    external moreThanZero(amountCollateral) moreThanZero(amountToMint) isAllowedToken(tokenCollateralAddress) payable {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintPio(amountToMint);
    }

    function redeemCollateralAndBurnPio(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBurn) override 
    external moreThanZero(amountCollateral) moreThanZero(amountToBurn) isAllowedToken(tokenCollateralAddress) nonReentrant {
        _burnPio(msg.sender, msg.sender, amountToBurn);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) override 
    external moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    function burn(uint256 amount) override external moreThanZero(amount) nonReentrant {
        _burnPio(msg.sender, msg.sender, amount);
    }

    function liquidate(address collateral, address user, uint256 debtToCover) override external moreThanZero(debtToCover) nonReentrant {
    }

    ////////////////////////
    // PUBLIC FUNCTIONS   //
    ////////////////////////
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) 
    public moreThanZero(amountCollateral) nonReentrant isAllowedToken(tokenCollateralAddress) {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert PIOEngine__TransferFailed();
        }
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    function mintPio(uint256 amount) public moreThanZero(amount) nonReentrant {
        s_pioMinted[msg.sender] += amount;
        _revertIfHealthFactorIsBroken(msg.sender);
        i_pio.mint(msg.sender, amount);
    }

    /////////////////////////////////////////////
    // PUBLIC & EXTERNAL VIEW & PURE FUNCTIONS //
    /////////////////////////////////////////////
    function getAccountInformation(address user) public view returns (uint256 totalPioMinted, uint256 collateralUSDValue) {
        return (s_pioMinted[user], getAccountCollateralValue(user));
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalUsdValueOfCollateral) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i].tokenAddress;
            uint256 amount = s_collateralDeposited[user][token];
            totalUsdValueOfCollateral += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e8 because it uses 8 decimal places
        return ((uint256(price) * ADDITIONAL_PRICE_FEED_PRECISION) * amount) / PRECISION;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    //////////////////////////////////////////////
    // Private & Internal View & Pure Functions //
    //////////////////////////////////////////////
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert PIOEngine__BreaksHealthFactor();   
        }
    }

    /**
     * @dev Returns how close to liquidation the user is. If a user goes below 1, then they can get liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total PIO minted / total collateral VALUE in USD
        (uint256 totalPioMinted, uint256 collateralValueInUsd) = getAccountInformation(user);
        if (totalPioMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        return (collateralAdjustedForThreshold * PRECISION) / totalPioMinted;
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) internal {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, from, to, true);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to, bool validateHealthFactor) internal {
        if (s_collateralDeposited[from][tokenCollateralAddress] < amountCollateral) {
            revert PioEngine__NotEnoughCollateral();
        }
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        if (validateHealthFactor) {
            _revertIfHealthFactorIsBroken(from);
        }
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert PIOEngine__TransferFailed();
        }
        emit PioEngineEvents.CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
    }

    function _burnPio(address onBehalfOf, address from, uint256 amount) private {
        if (s_pioMinted[onBehalfOf] < amount) {
            revert PioEngine__NotEnoughPio();
        }
        s_pioMinted[onBehalfOf] -= amount;
        i_pio.transferFrom(from, address(this), amount);
        i_pio.burn(amount);
    } 

}
