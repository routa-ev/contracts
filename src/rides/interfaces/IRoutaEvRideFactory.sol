// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.28;

import {IRoutaGeo} from './IRoutaGeo.sol';

interface IRoutaEvRideFactory is IRoutaGeo {
    error InvalidPayer();
    error InvalidSignature();
    error UsedOffChainReference();
    error NoSelfRide();

    struct DeploymentParams {
        address _token;
        uint256 _amountPayable;
        uint24 _feePercentageBps;
        uint24 _cancellationFeePercentageBps;
        GeoCoords _startCoords;
        GeoCoords _endCoords;
        bytes _packagedData;
        bytes _consolidatedSignature;
        string _offChainReference;
    }

    /// @notice Creates a new ride.
    /// @param _params The deployment parameters for the ride
    function deploy(DeploymentParams memory _params) external returns (address);

    /// @notice Returns the address of a ride by index.
    /// @param index The index of the ride to retrieve
    function allRides(uint256 index) external view returns (address);

    /// @notice Returns the total number of rides deployed.
    function allRidesLength() external view returns (uint256);

    /// @notice Returns the address of a ride using its off-chain reference.
    function offChainReference(
        string memory _reference
    ) external view returns (address);
}
