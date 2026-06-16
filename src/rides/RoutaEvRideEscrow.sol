pragma solidity >=0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract RoutaEvRideEscrow {
    address public payer;
    address public receiver;

    IERC20 public token;

    constructor(address _payer, address _receiver, IERC20 _token) {
        payer = _payer;
        receiver = _receiver;
        token = _token;
    }

    function deposit() external payable {}
}
