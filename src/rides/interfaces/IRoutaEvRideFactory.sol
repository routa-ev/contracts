// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.28;

import {IRoutaGeo} from './IRoutaGeo.sol';

interface IRoutaEvRideFactory is IRoutaGeo {
    error InvalidPayer();
    error InvalidSignature();

    /// @notice Creates a new ride.
    /// @param _token The address of the token
    /// @param _amountPayable The amount of tokens to be paid (driver's pay + fee)
    /// @param _feePercentageBps The fee percentage in basis points
    /// @param _cancellationFeePercentageBps The cancellation fee percentage in basis points
    /// @param _startCoords The starting coordinates of the ride
    /// @param _endCoords The ending coordinates of the ride
    /// @param _packagedData Concatenation of the transaction deadline, and the payer's permit signature
    /// @param _consolidatedSignature The concatenation of the payer's signature and the driver's signature for the ride
    /// @param _messageHash The hash of the message to be signed by the payer and driver
    function deploy(
        address _token,
        uint256 _amountPayable,
        uint24 _feePercentageBps,
        uint24 _cancellationFeePercentageBps,
        GeoCoords memory _startCoords,
        GeoCoords memory _endCoords,
        bytes calldata _packagedData,
        bytes calldata _consolidatedSignature,
        bytes32 _messageHash
    ) external returns (address);

    /// @notice Returns the address of a ride by index.
    /// @param index The index of the ride to retrieve
    function allRides(uint256 index) external view returns (address);

    /// @notice Returns the total number of rides deployed.
    function allRidesLength() external view returns (uint256);
}
