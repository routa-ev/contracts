pragma solidity >=0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

abstract contract BaseTransfer {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error AmountIsZero();
    error NotContract();

    function _transferERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) return;
        if (tokenAddress == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (tokenAddress.code.length == 0) revert NotContract();

        IERC20(tokenAddress).safeTransfer(to, amount);
    }

    function _transferFromERC20(
        address tokenAddress,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (tokenAddress == address(0)) revert ZeroAddress();
        if (from == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (tokenAddress.code.length == 0) revert NotContract();
        if (amount == 0) return;

        IERC20(tokenAddress).safeTransferFrom(from, to, amount);
    }

    function _transferNative(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) return;
        (bool sent, ) = to.call{value: amount}('');
        require(sent, 'Could not send out ether');
    }
}
