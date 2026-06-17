pragma solidity >=0.8.28;

import {IRoutaGeo} from './IRoutaGeo.sol';

interface IRoutaEvRide is IRoutaGeo {
    error AlreadyInitialized();
    error NotAContract();
    error NotAllowed();
    error AlreadySignedAction();
    error InvalidAction();

    enum Status {
        IN_PROGRESS,
        COMPLETED,
        CANCELLED
    }

    /// @notice Initializes the ride with the payer, driver, token, amount payable, fee percentage, cancellation fee percentage, start and end coordinates. Can only be called once.
    function initialize(
        address,
        address,
        address,
        uint256,
        uint24,
        uint24,
        GeoCoords memory,
        GeoCoords memory
    ) external;

    /// @notice Fulfills the ride. Needs to be called by both the payer and the driver.
    function fulfill(bytes memory signature) external;

    /// @notice Cancels the ride. Can only be called by the payer or the driver.
    function cancel(bytes memory signature) external;

    /// @notice Returns the address of the factory contract.
    function factory() external view returns (address);

    /// @notice Returns the current status of the ride.
    function status() external view returns (Status);

    /// @notice Returns the address of the escrow contract.
    function escrow() external view returns (address);

    /// @notice Returns the address of the payer.
    function payer() external view returns (address);

    /// @notice Returns the address of the driver.
    function driver() external view returns (address);

    /// @notice Returns the start time of the ride.
    function startTime() external view returns (uint256);

    /// @notice Returns the end time of the ride.
    function endTime() external view returns (uint256);

    /// @notice Returns the amount of tokens to be paid to the driver.
    function amountPayable() external view returns (uint256);

    /// @notice Returns the amount of tokens paid as fee.
    function feePaid() external view returns (uint256);

    /// @notice Returns the fee rate in basis points (bps).
    function feeBps() external view returns (uint24);

    /// @notice Returns the cancellation fee rate in basis points (bps).
    function cancellationFeeBps() external view returns (uint24);

    /// @notice Returns the start coordinates of the ride.
    function startCoords() external view returns (int256 lat, int256 lng);

    /// @notice Returns the end coordinates of the ride.
    function endCoords() external view returns (int256 lat, int256 lng);
}
