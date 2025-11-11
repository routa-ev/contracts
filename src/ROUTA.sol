pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./interfaces/IROUTA.sol";

contract ROUTA is ERC20Permit, IROUTA {
    address public immutable minter;

    constructor(
        address to,
        uint256 amount,
        address _minter
    ) ERC20Permit("Routa EV") ERC20("Routa EV", "ROUTA") {
        _mint(to, amount);
        minter = _minter;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter();
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter();
        _burn(to, amount);
    }
}
