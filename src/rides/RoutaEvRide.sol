pragma solidity >=0.8.28;

import {IRoutaEvRide} from './interfaces/IRoutaEvRide.sol';
import {IRoutaEvRideEscrow} from './interfaces/IRoutaEvRideEscrow.sol';
import {RoutaEvRideEscrow} from './RoutaEvRideEscrow.sol';
import {ERC2771Context} from '@openzeppelin/contracts/metatx/ERC2771Context.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

contract RoutaEvRide is IRoutaEvRide, ERC2771Context {
    address public payer;
    address public driver;
    address public factory;
    address public escrow;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public amountPayable;
    uint256 public feePaid;
    uint24 public feeBps;
    uint24 public cancellationFeeBps;
    uint24 public constant BASE_BPS = 10000;

    int256 public startLat;
    int256 public startLng;
    int256 public endLat;
    int256 public endLng;

    Status public status;

    mapping(address => bytes) private _signatures;

    bytes32 private _actionHash;

    constructor(address trustedForwarder_) ERC2771Context(trustedForwarder_) {}

    function initialize(
        address _payer,
        address _driver,
        address _token,
        uint256 _amountPayable,
        uint24 _feeBps,
        uint24 _cancellationFeeBps,
        GeoCoords memory _startCoords,
        GeoCoords memory _endCoords
    ) external {
        if (factory != address(0)) revert AlreadyInitialized();

        status = Status.IN_PROGRESS;
        payer = _payer;
        driver = _driver;

        factory = _msgSender(); // Would fall back to `msg.sender` since this function is called directly by the factory and not via a forwarder

        feeBps = _feeBps;
        feePaid = (_feeBps * _amountPayable) / BASE_BPS;
        amountPayable = _amountPayable - feePaid;

        cancellationFeeBps = _cancellationFeeBps;

        startLat = _startCoords.latitude;
        startLng = _startCoords.longitude;
        endLat = _endCoords.latitude;
        endLng = _endCoords.longitude;

        if (_token.code.length == 0) revert NotAContract();

        startTime = block.timestamp;

        escrow = address(new RoutaEvRideEscrow(_token));
    }

    function fulfill(bytes memory signature) external {
        bytes32 messageHash = keccak256(abi.encodePacked('RoutaEv:fulfill'));
        bytes32 signedHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        address signer = ECDSA.recover(signedHash, signature);

        if (_actionHash != bytes32(0) && _actionHash != messageHash)
            revert InvalidAction();
        if (signer != payer && signer != driver) revert NotAllowed();
        if (status != Status.IN_PROGRESS) revert NotAllowed();
        if (keccak256(_signatures[signer]) != keccak256(new bytes(0)))
            revert AlreadySignedAction();

        _signatures[signer] = signature;

        if (_actionHash == bytes32(0)) {
            _actionHash = messageHash;
        }

        bool payerSigned = keccak256(_signatures[payer]) !=
            keccak256(new bytes(0));
        bool driverSigned = keccak256(_signatures[driver]) !=
            keccak256(new bytes(0));

        if (payerSigned && driverSigned) {
            IRoutaEvRideEscrow(escrow).payout();
            endTime = block.timestamp;
            status = Status.COMPLETED;
        }
    }

    function startCoords() external view returns (int256 lat, int256 lng) {
        return (startLat, startLng);
    }

    function endCoords() external view returns (int256 lat, int256 lng) {
        return (endLat, endLng);
    }
}
