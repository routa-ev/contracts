pragma solidity >=0.8.28;

import {IRoutaEvRideFactory} from '../interfaces/IRoutaEvRideFactory.sol';
import {IRoutaEvRide} from '../interfaces/IRoutaEvRide.sol';
import {ERC2771Context} from '@openzeppelin/contracts/metatx/ERC2771Context.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Context} from '@openzeppelin/contracts/utils/Context.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

contract RoutaEVRideFactory is IRoutaEvRideFactory, ERC2771Context, Ownable {
    address public immutable rideImplementation;
    address[] public allRides;

    constructor(
        address _rideImplementation,
        address trustedForwarder_,
        address _owner
    ) ERC2771Context(trustedForwarder_) Ownable(_owner) {
        rideImplementation = _rideImplementation;
    }

    function deploy(
        address _token,
        uint256 _amountPayable,
        uint24 _feePercentageBps,
        GeoCoords memory _startCoords,
        GeoCoords memory _endCoords,
        bytes calldata _payerPermitData,
        bytes calldata _consolidatedSignature,
        bytes32 _messageHash
    ) external returns (address ride) {
        (bytes calldata a, bytes calldata b) = _splitConsolidatedSignature(
            _consolidatedSignature
        );

        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(
            _messageHash
        );

        address _payer = ECDSA.recover(ethSignedHash, a);
        address _driver = ECDSA.recover(ethSignedHash, b);

        _checkPayer(_payer);

        bytes32 salt = keccak256(
            abi.encodePacked(
                _payer,
                _driver,
                _token,
                _startCoords.latitude,
                _startCoords.longitude,
                _endCoords.latitude,
                _endCoords.longitude,
                block.timestamp // use block timestamp to ensure uniqueness
            )
        );

        ride = Clones.cloneDeterministic(rideImplementation, salt);
        allRides.push(ride);

        IRoutaEvRide(ride).initialize(
            _payer,
            _driver,
            _token,
            _amountPayable,
            _feePercentageBps,
            _startCoords,
            _endCoords,
            _payerPermitData
        );
    }

    function allRidesLength() external view returns (uint256) {
        return allRides.length;
    }

    function _checkPayer(address _payer) internal view {
        if (_payer != _msgSender()) revert InvalidPayer();
    }

    function _splitConsolidatedSignature(
        bytes calldata data
    ) internal pure returns (bytes calldata a, bytes calldata b) {
        require(data.length == 130, 'Invalid signature length');
        a = data[0:65];
        b = data[65:130];
    }

    function _msgSender()
        internal
        view
        override(ERC2771Context, Context)
        returns (address)
    {
        return ERC2771Context._msgSender();
    }

    function _msgData()
        internal
        view
        override(ERC2771Context, Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        override(ERC2771Context, Context)
        returns (uint256)
    {
        return ERC2771Context._contextSuffixLength();
    }
}
