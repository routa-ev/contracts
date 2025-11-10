pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./interfaces/IROUTA.sol";

contract ROUTA is ERC20Permit, IROUTA {
    constructor(
        address to,
        uint256 amount
    ) ERC20Permit("Routa Ev") ERC20("Routa EV", "ROUTA") {
        _mint(to, amount);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
