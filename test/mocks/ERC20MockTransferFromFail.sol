// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract ERC20MockTransferFromFail is ERC20Mock {
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
}
