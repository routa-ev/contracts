pragma solidity >=0.8.28;

import {IRoutaPaymentChannel} from './interfaces/IRoutaPaymentChannel.sol';
import {IRoutaPaymentFactory} from './interfaces/IRoutaPaymentFactory.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC2771Context} from '@openzeppelin/contracts/metatx/ERC2771Context.sol';
import {Context} from '@openzeppelin/contracts/utils/Context.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

contract RoutaPaymentFactory is IRoutaPaymentFactory, Ownable, ERC2771Context {
    address public immutable channelImplementation;

    address[] public allPaymentChannels;
    mapping(string => address) public offChainSlugToPaymentChannel;

    constructor(
        address _channelImplementation,
        address trustedForwarder_,
        address team
    ) Ownable(team) ERC2771Context(trustedForwarder_) {
        channelImplementation = _channelImplementation;
    }

    function deploy(
        DeploymentParams memory _params
    ) external returns (address _paymentChannel) {
        address sender = _msgSender();
        bytes32 salt = keccak256(
            abi.encodePacked(_params._offChainSlug, sender, _params._tokens)
        );

        _paymentChannel = Clones.cloneDeterministic(
            channelImplementation,
            salt
        );

        IRoutaPaymentChannel(_paymentChannel).initialize(
            _params._tokens,
            sender,
            _params._receiver,
            _params._offChainSlug
        );

        offChainSlugToPaymentChannel[_params._offChainSlug] = _paymentChannel;
        allPaymentChannels.push(_paymentChannel);
    }

    function allPaymentChannelsLength() public view returns (uint256) {
        return allPaymentChannels.length;
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
