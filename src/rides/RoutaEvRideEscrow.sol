pragma solidity >=0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IRoutaEvRideEscrow} from './interfaces/IRoutaEvRideEscrow.sol';
import {IRoutaEvRide} from './interfaces/IRoutaEvRide.sol';
import {BaseTransfer} from '../payments/base/BaseTransfer.sol';

contract RoutaEvRideEscrow is IRoutaEvRideEscrow, BaseTransfer {
    address public immutable token;
    address public immutable factory;
    address public immutable feeRecipient;

    constructor(address _token) BaseTransfer() {
        token = _token;
        factory = msg.sender;

        feeRecipient = Ownable(IRoutaEvRide(msg.sender).factory()).owner();
    }

    function deposit() external {
        address sender = msg.sender;
        address rideFactory = IRoutaEvRide(factory).factory();
        uint256 amount = IRoutaEvRide(factory).amountPayable();
        uint256 fee = IRoutaEvRide(factory).feePaid();

        if (sender != rideFactory) revert OnlyBaseFactory();
        _transferFromERC20(token, sender, address(this), amount + fee);
    }

    function payout() external {
        address sender = msg.sender;
        if (sender != factory) revert OnlyFactory();

        uint256 amount = IRoutaEvRide(sender).amountPayable();
        uint256 fee = IRoutaEvRide(sender).feePaid();
        address driver = IRoutaEvRide(sender).driver();

        // Pay driver
        _transferERC20(token, driver, amount);
        // Pay fee
        _transferERC20(token, feeRecipient, fee);
    }

    function emergencyPayout(address to, uint256 amount) external {
        if (msg.sender != factory) revert OnlyFactory();
        _transferERC20(token, to, amount);
    }
}
