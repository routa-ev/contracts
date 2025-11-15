pragma solidity >=0.8.28;

interface IROUTA {
    error OnlyMinter();
    error ZeroAddressMinter();
    error MinterAlreadySet();

    function minter() external view returns (address);

    function mint(address to, uint256 amount) external;

    function burn(address to, uint256 amount) external;

    function setMinter(address newMinter) external;
}
