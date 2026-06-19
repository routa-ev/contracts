pragma solidity >=0.8.28;

import {ERC2771Forwarder} from '@openzeppelin/contracts/metatx/ERC2771Forwarder.sol';
import {AccessControl} from '@openzeppelin/contracts/access/AccessControl.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

contract RoutaCustomForwarder is ERC2771Forwarder, AccessControl, Ownable {
    error NotAllowedRelayer(address sender);

    bytes32 public constant allowedRelayerRole = keccak256('ALLOWED_RELAYER');

    constructor(
        address _relayer
    ) ERC2771Forwarder('RoutaEvCustomForwarder') Ownable(msg.sender) {
        _grantRole(allowedRelayerRole, _relayer);
    }

    function _execute(
        ForwardRequestData calldata _request,
        bool _requireValidRequest
    ) internal virtual override returns (bool) {
        if (!hasRole(allowedRelayerRole, msg.sender)) {
            revert NotAllowedRelayer(msg.sender);
        }
        return super._execute(_request, _requireValidRequest);
    }

    function appointRelayer(address _relayer) external onlyOwner {
        _grantRole(allowedRelayerRole, _relayer);
    }
}
