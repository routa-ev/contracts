pragma solidity >=0.8.28;

import {ERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import {IROUTA} from './interfaces/IROUTA.sol';

contract ROUTA is ERC20Permit, IROUTA {
    address public minter;

    constructor() ERC20Permit('Routa EV') ERC20('Routa EV', 'ROUTA') {}

    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter();
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter();
        _burn(to, amount);
    }

    function setMinter(address newMinter) external {
        if (minter != address(0)) revert MinterAlreadySet();
        if (newMinter == address(0)) revert ZeroAddressMinter();
        minter = newMinter;
    }
}
