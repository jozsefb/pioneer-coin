// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.24;

/**
 * @title PioEngine
 * @author Jozsef Benczedi
 * The system is designed to be as minimal as possible,
 *  and have the tokens maintain a 1 token == 1 USD value.
 * This stable coin has the properties:
 *  - Collateral: Exogenous (ETH & BTC)
 *  - Minting: Algorithmic
 *  - Relative Stability: Pegged to USD
 * 
 * It is similar to DAI.... 
 * Based on https://github.com/Cyfrin/foundry-full-course-cu?tab=readme-ov-file#lesson-12-foundry-defi--stablecoin-the-pinnacle-project-get-here
 * 
 * Our Pioneer system should always be "overcollaterized". At no point should 
 * the vaule of all collateral <= the value of all PIO
 * 
 * @notice This contract is the core of the PIO system. It handles all the logic
 * for mining and redeeming PIO, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on MakerDao DSS (DAI) system.
 * 
 */
interface PioEngine {
    enum CollateralToken {BTC, ETH}
    struct TokenDetails {
        CollateralToken token;
        address tokenAddress;
        address pricefeedAddress;
        bool exists;    // If the token exists or not, useful to check if a mapping was set for the token
    }

    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountToMint: The amount of PIO you want to mint
     * @notice This function will deposit your collateral and mint PIO in one transaction
     */
    function depositCollateralAndMintPio(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToMint) external;

    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountToBurn: The amount of PIO you want to burn
     * @notice This function will withdraw your collateral and burn PIO in one transaction
     */
    function redeemCollateralForPio(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBurn) external;

    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have PIO minted, you will not be able to redeem until you burn your PIO
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;

    /**
     * @notice careful! You'll burn your PIO here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn some PIO  but keep your collateral in.
     */
    function burn(uint256 amount) external;

    /**
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again. 
     * This is collateral that you're going to take from the user who is insolvent. 
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     * @notice You can partially liquidate a user.
     * @notice You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone. 
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
    */
    function liquidate(address collateral, address user, uint256 debtToCover) external;
}
