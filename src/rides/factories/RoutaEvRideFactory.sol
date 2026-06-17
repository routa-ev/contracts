pragma solidity >=0.8.28;

import {BaseTransfer} from '../../payments/base/BaseTransfer.sol';
import {IRoutaEvRideFactory} from '../interfaces/IRoutaEvRideFactory.sol';
import {IRoutaEvRide} from '../interfaces/IRoutaEvRide.sol';
import {IRoutaEvRideEscrow} from '../interfaces/IRoutaEvRideEscrow.sol';
import {ERC2771Context} from '@openzeppelin/contracts/metatx/ERC2771Context.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Context} from '@openzeppelin/contracts/utils/Context.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract RoutaEVRideFactory is
    IRoutaEvRideFactory,
    ERC2771Context,
    Ownable,
    BaseTransfer
{
    address public immutable rideImplementation;

    /// @inheritdoc IRoutaEvRideFactory
    address[] public allRides;

    constructor(
        address _rideImplementation,
        address trustedForwarder_,
        address _team
    ) ERC2771Context(trustedForwarder_) Ownable(_team) BaseTransfer() {
        rideImplementation = _rideImplementation;
    }

    /// @inheritdoc IRoutaEvRideFactory
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
            _cancellationFeePercentageBps,
            _startCoords,
            _endCoords
        );

        // Get transacton deadline and payer's permit signature
        (uint256 deadline, bytes memory permitSignature) = abi.decode(
            _packagedData,
            (uint256, bytes)
        );

        // Verify the permit signature
        (uint8 v, bytes32 r, bytes32 s) = _getVRSFromSignature(permitSignature);

        IERC20Permit(_token).permit(
            _payer,
            address(this),
            _amountPayable,
            deadline,
            v,
            r,
            s
        );

        // Transfer the tokens from the payer to this contract
        _transferFromERC20(_token, _payer, address(this), _amountPayable);

        address escrow = IRoutaEvRide(ride).escrow();

        // Approve escrow's spending of exact amount
        IERC20(_token).approve(escrow, _amountPayable);
        // Call `deposit` on escrow
        IRoutaEvRideEscrow(escrow).deposit();
    }

    /// @inheritdoc IRoutaEvRideFactory
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

    function _getVRSFromSignature(
        bytes memory data
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(data.length == 65, 'Invalid signature length');

        assembly {
            r := mload(add(data, 32))
            s := mload(add(data, 64))
            v := byte(0, mload(add(data, 96)))
        }
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

    function withdrawAsset(
        address asset,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (asset == address(0)) {
            _transferNative(to, amount);
        } else {
            _transferERC20(asset, to, amount);
        }
    }
}
