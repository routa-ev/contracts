pragma solidity >=0.8.28;

import {IRoutaEvRide} from './interfaces/IRoutaEvRide.sol';
import {IRoutaEvRideEscrow} from './interfaces/IRoutaEvRideEscrow.sol';
import {RoutaEvRideEscrow} from './RoutaEvRideEscrow.sol';
import {ERC2771Context} from '@openzeppelin/contracts/metatx/ERC2771Context.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

contract RoutaEvRide is IRoutaEvRide, ERC2771Context {
    /// @inheritdoc IRoutaEvRide
    address public payer;
    /// @inheritdoc IRoutaEvRide
    address public driver;
    /// @inheritdoc IRoutaEvRide
    address public factory;
    /// @inheritdoc IRoutaEvRide
    address public escrow;

    /// @inheritdoc IRoutaEvRide
    uint256 public startTime;
    /// @inheritdoc IRoutaEvRide
    uint256 public endTime;
    /// @inheritdoc IRoutaEvRide
    uint256 public amountPayable;
    /// @inheritdoc IRoutaEvRide
    uint256 public feePaid;
    /// @inheritdoc IRoutaEvRide
    uint24 public feeBps;
    /// @inheritdoc IRoutaEvRide
    uint24 public cancellationFeeBps;
    uint24 internal constant BASE_BPS = 10000;

    int256 public startLat;
    int256 public startLng;
    int256 public endLat;
    int256 public endLng;

    /// @inheritdoc IRoutaEvRide
    Status public status;

    mapping(address => bytes) private _fulfillmentSignatures;

    bytes32 private _actionHash;

    constructor(address trustedForwarder_) ERC2771Context(trustedForwarder_) {}

    /// @inheritdoc IRoutaEvRide
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

        emit StatusChanged(Status.IN_PROGRESS, startTime);
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
        if (
            keccak256(_fulfillmentSignatures[signer]) != keccak256(new bytes(0))
        ) revert AlreadySignedAction();

        _fulfillmentSignatures[signer] = signature;

        bool payerSigned = keccak256(_fulfillmentSignatures[payer]) !=
            keccak256(new bytes(0));
        bool driverSigned = keccak256(_fulfillmentSignatures[driver]) !=
            keccak256(new bytes(0));

        if (payerSigned && driverSigned) {
            IRoutaEvRideEscrow(escrow).payout();
            endTime = block.timestamp;
            status = Status.COMPLETED;
            emit StatusChanged(Status.COMPLETED, endTime);
        }

        if (_actionHash == bytes32(0)) {
            _actionHash = messageHash;
        }
    }

    function cancel(bytes memory signature) external {
        bytes32 messageHash = keccak256(abi.encodePacked('RoutaEv:cancel'));
        bytes32 signedHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        address signer = ECDSA.recover(signedHash, signature);

        if (_actionHash != bytes32(0) && _actionHash != messageHash)
            revert InvalidAction();

        if (signer != payer && signer != driver) revert NotAllowed();
        if (status != Status.IN_PROGRESS) revert NotAllowed();

        if (signer == payer) {
            uint256 penalty = (cancellationFeeBps * amountPayable) / BASE_BPS;
            // Transfer penalty fee to the driver
            IRoutaEvRideEscrow(escrow).emergencyPayout(driver, penalty);
            // Transfer remaining funds to the payer
            uint256 remaining = amountPayable - penalty;
            IRoutaEvRideEscrow(escrow).emergencyPayout(payer, remaining);
            // Transfer fees to the fee receiver
            address feeReceiver = IRoutaEvRideEscrow(escrow).feeRecipient();
            IRoutaEvRideEscrow(escrow).emergencyPayout(feeReceiver, feePaid);
        } else if (signer == driver) {
            // Refund the payer
            IRoutaEvRideEscrow(escrow).emergencyPayout(payer, amountPayable);
            // Transfer fees to the fee receiver
            address feeReceiver = IRoutaEvRideEscrow(escrow).feeRecipient();
            IRoutaEvRideEscrow(escrow).emergencyPayout(feeReceiver, feePaid);
        }

        if (_actionHash == bytes32(0)) {
            _actionHash = messageHash;
        }

        endTime = block.timestamp;
        status = Status.CANCELLED;
        emit StatusChanged(Status.CANCELLED, endTime);
    }

    function emergencyCancel(
        uint256 _payerAmount,
        uint256 _driverAmount
    ) external {
        address sender = _msgSender();
        address team = Ownable(factory).owner();

        if (sender != team) revert OnlyTeam();

        require(
            _payerAmount + _driverAmount == amountPayable,
            'Invalid amounts'
        );

        IRoutaEvRideEscrow(escrow).emergencyPayout(payer, _payerAmount);
        IRoutaEvRideEscrow(escrow).emergencyPayout(driver, _driverAmount);
        // Transfer remaining funds to the fee receiver
        address feeReceiver = IRoutaEvRideEscrow(escrow).feeRecipient();
        IRoutaEvRideEscrow(escrow).emergencyPayout(feeReceiver, feePaid);

        endTime = block.timestamp;
        status = Status.CANCELLED;
        emit StatusChanged(Status.CANCELLED, endTime);
    }

    function startCoords() external view returns (int256 lat, int256 lng) {
        return (startLat, startLng);
    }

    function endCoords() external view returns (int256 lat, int256 lng) {
        return (endLat, endLng);
    }
}
