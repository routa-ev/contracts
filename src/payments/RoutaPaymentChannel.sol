pragma solidity >=0.8.28;

import {IRoutaPaymentChannel} from './interfaces/IRoutaPaymentChannel.sol';
import {IRoutaPaymentFactory} from './interfaces/IRoutaPaymentFactory.sol';
import {BaseTransfer} from './base/BaseTransfer.sol';
import {ERC2771Context} from '@openzeppelin/contracts/metatx/ERC2771Context.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Context} from '@openzeppelin/contracts/utils/Context.sol';
import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

contract RoutaPaymentChannel is
    IRoutaPaymentChannel,
    ERC2771Context,
    BaseTransfer,
    Ownable,
    ReentrancyGuard
{
    address public constant ETHER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public factory;
    address public receiver;

    address[] public paymentTokens;

    string public offChainSlug;

    ChannelStatus public status;

    mapping(bytes32 => Payment) private _payments;
    mapping(bytes32 => string) public paymentOffChainReference;
    mapping(string => bytes32) public paymentIdFromOffChainReference;

    bytes32[] public payments;

    uint24 public constant BASE_BPS = 10000;

    constructor(
        address trustedForwarder_
    )
        ERC2771Context(trustedForwarder_)
        BaseTransfer()
        Ownable(msg.sender)
        ReentrancyGuard()
    {}

    function initialize(
        address[] memory _paymentTokens,
        address _owner,
        address _receiver,
        string memory _offChainSlug
    ) external {
        if (factory != address(0)) revert AlreadyInitialized();

        factory = _msgSender();
        receiver = _receiver;
        paymentTokens = _paymentTokens;
        offChainSlug = _offChainSlug;

        status = ChannelStatus.Active;

        _transferOwnership(_owner);

        emit Initialized(
            _paymentTokens,
            _owner,
            _receiver,
            _offChainSlug,
            block.timestamp
        );
    }

    function payWithERC20(
        address _token,
        uint256 _amount,
        bytes memory _data
    ) external nonReentrant returns (bytes32 _paymentId) {
        address sender = _msgSender();

        _checkActive();
        _checkTokenIsAllowed(_token);
        _forceUseNative(_token);

        // Decode permit signature and other parameters from the _data payload
        (
            bytes memory permitSignature,
            string memory memo,
            string memory ref,
            bool releaseImmediately,
            uint256 deadline
        ) = abi.decode(_data, (bytes, string, string, bool, uint256));
        (uint8 v, bytes32 r, bytes32 s) = _getVRSFromSignature(permitSignature);

        _ensurePristineReference(ref);

        // Submit permit signature to the ERC20Permit contract
        IERC20Permit(_token).permit(
            sender,
            address(this),
            _amount,
            deadline,
            v,
            r,
            s
        );

        uint256 fee = (IRoutaPaymentFactory(factory).FEE() * _amount) /
            BASE_BPS;

        address feeRecipient = Ownable(factory).owner();

        // Transfer the token from the sender to this contract
        _transferFromERC20(_token, sender, address(this), _amount - fee);
        // Transfer the fee to the factory
        _transferFromERC20(_token, sender, feeRecipient, fee);

        // Compose payment
        Payment memory payment = Payment({
            _token: _token,
            _amount: _amount - fee,
            _payer: sender,
            _released: releaseImmediately,
            _revoked: false,
            _refunded: false,
            _createdAt: block.timestamp,
            _memo: memo
        });

        _paymentId = keccak256(abi.encode(payment, ref));
        _payments[_paymentId] = payment;
        paymentOffChainReference[_paymentId] = ref;
        paymentIdFromOffChainReference[ref] = _paymentId;
        payments.push(_paymentId);

        emit NewPayment(
            _paymentId,
            sender,
            _token,
            _amount - fee,
            memo,
            block.timestamp
        );
    }

    function payWithNative(
        uint256 _amount,
        bytes memory _data
    ) external payable nonReentrant returns (bytes32 _paymentId) {
        address sender = _msgSender();
        address _token = ETHER;

        _checkActive();

        // Decode payload
        (
            string memory memo,
            string memory ref,
            bool releaseImmediately,
            uint256 deadline
        ) = abi.decode(_data, (string, string, bool, uint256));

        if (block.timestamp >= deadline) revert Deadline();

        _ensurePristineReference(ref);
        require(_amount == msg.value);

        uint256 fee = (IRoutaPaymentFactory(factory).FEE() * _amount) /
            BASE_BPS;

        address feeRecipient = Ownable(factory).owner();

        // Transfer the fee to the factory
        _transferNative(feeRecipient, fee);

        // Compose payment
        Payment memory payment = Payment({
            _token: _token,
            _amount: _amount - fee,
            _payer: sender,
            _released: releaseImmediately,
            _revoked: false,
            _refunded: false,
            _createdAt: block.timestamp,
            _memo: memo
        });

        _paymentId = keccak256(abi.encode(payment, ref));
        _payments[_paymentId] = payment;
        paymentOffChainReference[_paymentId] = ref;
        paymentIdFromOffChainReference[ref] = _paymentId;
        payments.push(_paymentId);

        emit NewPayment(
            _paymentId,
            sender,
            _token,
            _amount - fee,
            memo,
            block.timestamp
        );
    }

    function claim(bytes32 _paymentId, uint256 _amount) external nonReentrant {
        _checkOwner();

        Payment storage payment = _payments[_paymentId];

        if (!payment._released) revert NotReleased();
        if (payment._revoked) revert AlreadyRevoked();
        if (payment._refunded) revert AlreadyRefunded();
        if (payment._amount == 0) revert AlreadyDrained();
        if (_amount > payment._amount) revert NotEnoughBalance();

        if (payment._token == ETHER) {
            _transferNative(receiver, _amount);
        } else {
            _transferERC20(payment._token, receiver, _amount);
        }

        payment._amount -= _amount;

        emit Payout(
            _paymentId,
            payment._token,
            receiver,
            _amount,
            block.timestamp
        );
    }

    function releasePayment(bytes32 _paymentId) external nonReentrant {
        address sender = _msgSender();
        Payment storage payment = _payments[_paymentId];

        if (payment._revoked) revert AlreadyRevoked();
        if (payment._refunded) revert AlreadyRefunded();
        if (payment._released) revert AlreadyReleased();

        if (payment._payer != sender) revert OnlyPayer();

        payment._released = true;
        emit ReleasePayment(_paymentId, block.timestamp);
    }

    function refundPayment(bytes32 _paymentId) external nonReentrant {
        _checkOwner();
        Payment storage payment = _payments[_paymentId];

        if (payment._revoked) revert AlreadyRevoked();
        if (payment._refunded) revert AlreadyRefunded();
        if (payment._released) revert AlreadyReleased();

        if (payment._token == ETHER) {
            _transferNative(payment._payer, payment._amount);
        } else {
            _transferERC20(payment._token, payment._payer, payment._amount);
        }

        payment._refunded = true;
        payment._amount = 0;
        emit RefundPayment(_paymentId, block.timestamp);
    }

    function revokePayment(bytes32 _paymentId) external nonReentrant {
        address sender = _msgSender();

        Payment storage payment = _payments[_paymentId];

        if (payment._revoked) revert AlreadyRevoked();
        if (payment._refunded) revert AlreadyRefunded();
        if (payment._released) revert AlreadyReleased();
        if (sender != payment._payer) revert OnlyPayer();

        if (payment._token == ETHER) {
            _transferNative(payment._payer, payment._amount);
        } else {
            _transferERC20(payment._token, payment._payer, payment._amount);
        }

        payment._revoked = true;
        payment._amount = 0;
        emit RevokePayment(_paymentId, block.timestamp);
    }

    function emergencyRelease(
        bytes32 _paymentId,
        address _receiver
    ) external nonReentrant {
        address sender = _msgSender();
        address team = Ownable(factory).owner();

        if (sender != team) revert OnlyTeam();

        Payment storage payment = _payments[_paymentId];

        if (payment._revoked) revert AlreadyRevoked();
        if (payment._refunded) revert AlreadyRefunded();
        if (payment._released) revert AlreadyReleased();

        if (payment._token == ETHER) {
            _transferNative(_receiver, payment._amount);
        } else {
            _transferERC20(payment._token, _receiver, payment._amount);
        }

        payment._released = true;
        payment._amount = 0;
        emit EmergencyReleasePayment(_paymentId, block.timestamp);
    }

    function close() external {
        _checkOwner();

        if (status == ChannelStatus.Closed) revert ChannelNotActive();

        status = ChannelStatus.Closed;
        emit ChannelStatusChanged(ChannelStatus.Closed, block.timestamp);
    }

    function activate() external {
        _checkOwner();

        if (status == ChannelStatus.Active) revert ChannelAlreadyActive();

        status = ChannelStatus.Active;
        emit ChannelStatusChanged(ChannelStatus.Active, block.timestamp);
    }

    function paymentTokensLength() external view returns (uint256) {
        return paymentTokens.length;
    }

    function getPayment(
        bytes32 paymentId
    )
        external
        view
        returns (
            address _token,
            uint256 _amount,
            address _payer,
            bool _released,
            bool _revoked,
            bool _refunded,
            uint256 _createdAt,
            string memory _memo
        )
    {
        Payment memory payment = _payments[paymentId];
        _token = payment._token;
        _amount = payment._amount;
        _payer = payment._payer;
        _released = payment._released;
        _revoked = payment._revoked;
        _refunded = payment._refunded;
        _createdAt = payment._createdAt;
        _memo = payment._memo;
    }

    function paymentsLength() external view returns (uint256) {
        return payments.length;
    }

    function _checkTokenIsAllowed(address token) internal view {
        bool allowed = false;
        for (uint256 i = 0; i < paymentTokens.length; i++) {
            if (paymentTokens[i] == token) {
                allowed = true;
                break;
            }
        }
        if (!allowed) revert TokenNotAllowed();
    }

    function _ensurePristineReference(string memory ref) internal view {
        if (paymentIdFromOffChainReference[ref] != bytes32(0))
            revert ReferenceAlreadyUsed();
    }

    function _forceUseNative(address token) internal pure {
        if (token == ETHER) revert UsePayNative();
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

    function _checkActive() internal view {
        if (status != ChannelStatus.Active) revert ChannelNotActive();
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
