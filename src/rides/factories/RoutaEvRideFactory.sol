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
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';

contract RoutaEvRideFactory is
    IRoutaEvRideFactory,
    ERC2771Context,
    EIP712,
    Ownable,
    BaseTransfer
{
    address public immutable rideImplementation;

    /// @inheritdoc IRoutaEvRideFactory
    address[] public allRides;

    /// @inheritdoc IRoutaEvRideFactory
    mapping(string => address) public offChainReference;

    bytes32 public constant RIDE_TYPEHASH =
        keccak256(
            'Ride(address _token,uint256 _amountPayable,bytes32 _startCoordsHash,bytes32 _endCoordsHash,bytes32 _offChainReferenceHash)'
        );

    constructor(
        address _rideImplementation,
        address trustedForwarder_,
        address _team
    )
        ERC2771Context(trustedForwarder_)
        Ownable(_team)
        EIP712('RoutaEvRideFactory', '1')
        BaseTransfer()
    {
        rideImplementation = _rideImplementation;
    }

    /// @inheritdoc IRoutaEvRideFactory
    function deploy(
        DeploymentParams memory _params
    ) external returns (address ride) {
        (bytes memory a, bytes memory b) = _splitConsolidatedSignature(
            _params._consolidatedSignature
        );

        bytes32 structHash = keccak256(
            abi.encode(
                RIDE_TYPEHASH,
                _params._token,
                _params._amountPayable,
                keccak256(abi.encode(_params._startCoords)),
                keccak256(abi.encode(_params._endCoords)),
                keccak256(bytes(_params._offChainReference))
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);

        address _payer = ECDSA.recover(digest, a);
        address _driver = ECDSA.recover(digest, b);

        if (_payer == _driver) revert NoSelfRide();

        _checkPayer(_payer);
        _checkOffChainReference(_params._offChainReference);

        bytes32 salt = keccak256(
            abi.encodePacked(
                _payer,
                _driver,
                _params._token,
                _params._startCoords.latitude,
                _params._startCoords.longitude,
                _params._endCoords.latitude,
                _params._endCoords.longitude,
                _params._offChainReference,
                block.timestamp // use block timestamp to ensure uniqueness
            )
        );

        ride = Clones.cloneDeterministic(rideImplementation, salt);
        allRides.push(ride);
        offChainReference[_params._offChainReference] = ride;

        IRoutaEvRide(ride).initialize(
            _payer,
            _driver,
            _params._token,
            _params._amountPayable,
            _params._feePercentageBps,
            _params._cancellationFeePercentageBps,
            _params._startCoords,
            _params._endCoords
        );

        // Get transacton deadline and payer's permit signature
        (uint256 deadline, bytes memory permitSignature) = abi.decode(
            _params._packagedData,
            (uint256, bytes)
        );

        // Verify the permit signature
        (uint8 v, bytes32 r, bytes32 s) = _getVRSFromSignature(permitSignature);

        IERC20Permit(_params._token).permit(
            _payer,
            address(this),
            _params._amountPayable,
            deadline,
            v,
            r,
            s
        );

        // Transfer the tokens from the payer to this contract
        _transferFromERC20(
            _params._token,
            _payer,
            address(this),
            _params._amountPayable
        );

        address escrow = IRoutaEvRide(ride).escrow();

        // Approve escrow's spending of exact amount
        IERC20(_params._token).approve(escrow, _params._amountPayable);
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

    function _checkOffChainReference(string memory _reference) internal view {
        if (offChainReference[_reference] != address(0))
            revert UsedOffChainReference();
    }

    function _splitConsolidatedSignature(
        bytes memory data
    ) internal pure returns (bytes memory a, bytes memory b) {
        require(data.length == 130, 'Invalid signature length');

        a = new bytes(65);
        b = new bytes(65);

        for (uint256 i; i < 65; ++i) {
            a[i] = data[i];
            b[i] = data[i + 65];
        }
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
