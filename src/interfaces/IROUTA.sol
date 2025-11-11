pragma solidity >=0.8.28;

interface IROUTA {
    error OnlyMinter();

    function minter() external view returns (address);

    function mint(address to, uint256 amount) external;
}
