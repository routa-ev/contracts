pragma solidity >=0.8.28;

interface IRoutaEvRideEscrow {
    error OnlyBaseFactory();
    error OnlyFactory();

    /// @notice Deposits funds into the escrow. Can be called by anyone, and just once.
    function deposit() external;

    /// @notice Sends funds from the escrow to the receiver. Can be called only by the factory contract.
    function payout() external;

    /// @notice Sends funds from the escrow to the receiver. Can be called only by the factory contract.
    function emergencyPayout(address to, uint256 amount) external;

    /// @notice Returns the address of the factory contract.
    function factory() external view returns (address);

    /// @notice Returns the address of the fee recipient.
    function feeRecipient() external view returns (address);

    /// @notice Returns the address of the token contract.
    function token() external view returns (address);
}
