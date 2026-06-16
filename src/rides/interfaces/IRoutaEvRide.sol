pragma solidity >=0.8.28;

import {IRoutaGeo} from './IRoutaGeo.sol';

interface IRoutaEvRide is IRoutaGeo {
    enum Status {
        IN_PROGRESS,
        COMPLETED,
        CANCELLED
    }

    /// @notice Initializes the ride with the payer, driver, token, amount payable, fee percentage, start and end coordinates, and payer's permit call. Can only be called once.
    function initialize(
        address,
        address,
        address,
        uint256,
        uint24,
        GeoCoords memory,
        GeoCoords memory,
        bytes calldata
    ) external;

    /// @notice Cancels the ride. Can only be called by the payer or the driver.
    function cancel() external;

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

    /// @notice Returns the amount of tokens paid to the escrow.
    function amountPaid() external view returns (uint256);

    /// @notice Returns the fee rate in basis points (bps).
    function feeBps() external view returns (uint24);

    /// @notice Returns the start coordinates of the ride.
    function startCoords() external view returns (GeoCoords memory);

    /// @notice Returns the end coordinates of the ride.
    function endCoords() external view returns (GeoCoords memory);
}
