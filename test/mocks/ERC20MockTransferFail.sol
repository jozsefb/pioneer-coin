// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20ReturnFalseMock, ERC20} from "@openzeppelin/contracts/mocks/token/ERC20ReturnFalseMock.sol";

contract ERC20MockTransferFail is ERC20ReturnFalseMock {
    constructor() ERC20("Mock", "MOCK") {}
}
