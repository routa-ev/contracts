pragma solidity >=0.8.28;

import {console} from 'forge-std/console.sol';
import {Test} from 'forge-std/Test.sol';
import {IRoutaGeo} from '../src/rides/interfaces/IRoutaGeo.sol';
import {IRoutaEvRideFactory} from '../src/rides/interfaces/IRoutaEvRideFactory.sol';
import {RoutaEvRideFactory} from '../src/rides/factories/RoutaEvRideFactory.sol';
import {IRoutaEvRide} from '../src/rides/interfaces/IRoutaEvRide.sol';
import {RoutaEvRide} from '../src/rides/RoutaEvRide.sol';
import {RoutaCustomForwarder} from '../src/RoutaCustomForwarder.sol';
import {ROUTA} from '../src/ROUTA.sol';
import {Utils} from './utils/_.sol';
import {ERC2771Forwarder} from '@openzeppelin/contracts/metatx/ERC2771Forwarder.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

contract RidesTest is Test {
    using Utils for string;

    RoutaEvRideFactory public factory;
    RoutaCustomForwarder public forwarder;
    ROUTA public routa;

    string public offChainReference;
    string private hashable = '__test__signable__message__';

    bytes32 private messageHash;
    address[] private wallets;

    address private token;

    uint24 private constant BASE_PS = 10000;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256(
            'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
        );

    bytes32 internal constant FORWARD_REQUEST_TYPEHASH =
        keccak256(
            'ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)'
        );

    uint256 private teamPk = 0xD0E;
    uint256 private payerPk = 0xA11CE;
    uint256 private driverPk = 0xB0B;

    address private team;
    address private payer;
    address private driver;

    function setUp() public {
        initParams();
        RoutaEvRide implementation = new RoutaEvRide(address(forwarder));
        factory = new RoutaEvRideFactory(
            address(implementation),
            address(forwarder),
            team
        );
    }

    function initParams() public {
        team = vm.addr(teamPk);
        payer = vm.addr(payerPk);
        driver = vm.addr(driverPk);
        forwarder = new RoutaCustomForwarder(team);

        console.log('=== Initialized addresses ===');
        console.log('Team:', team);
        console.log('Payer:', payer);
        console.log('Driver:', driver);
        console.log('=== Completed account setup ===');

        offChainReference = string(
            abi.encodePacked('REF-', vm.toString(block.timestamp))
        );

        console.log('Off-Chain Reference:', offChainReference);

        messageHash = MessageHashUtils.toEthSignedMessageHash(
            hashable.generateHash()
        );

        console.log('Message Hash:', vm.toString(messageHash));

        routa = new ROUTA();
        routa.setMinter(team);

        vm.prank(team);
        routa.mint(payer, 170000000 ether);

        token = address(routa);
    }

    function createGeoCoords(
        int256 latitude,
        int256 longitude
    ) public pure returns (IRoutaGeo.GeoCoords memory) {
        return IRoutaGeo.GeoCoords({latitude: latitude, longitude: longitude});
    }

    function createPackagedData() public view returns (bytes memory) {
        uint256 deadline = block.timestamp + 1 hours;

        // Sign permit message
        uint256 nonce = routa.nonces(payer);
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                payer,
                address(factory),
                12 ether,
                nonce,
                deadline
            )
        );
        bytes32 domainSeparator = routa.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(
            abi.encodePacked('\x19\x01', domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        return abi.encode(deadline, sig);
    }

    function createConsolidatedSignature() public view returns (bytes memory) {
        (uint8 v0, bytes32 r0, bytes32 s0) = vm.sign(payerPk, messageHash);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(driverPk, messageHash);
        return
            abi.encodePacked(
                abi.encodePacked(r0, s0, v0),
                abi.encodePacked(r1, s1, v1)
            );
    }

    function runDeploymentTest() public {
        IRoutaEvRideFactory.DeploymentParams memory params = IRoutaEvRideFactory
            .DeploymentParams({
                _offChainReference: offChainReference,
                _messageHash: hashable.generateHash(),
                _token: token,
                _amountPayable: 12 ether,
                _feePercentageBps: 200,
                _cancellationFeePercentageBps: 100,
                _startCoords: createGeoCoords(0, 0),
                _endCoords: createGeoCoords(0, 0),
                _packagedData: createPackagedData(),
                _consolidatedSignature: createConsolidatedSignature()
            });

        address from = payer;
        address to = address(factory);
        uint256 value = 0;
        uint256 gas = 1000000;
        uint256 nonce = forwarder.nonces(from);
        uint48 deadline = uint48(block.timestamp + 1 days);
        bytes memory data = abi.encodeWithSelector(
            IRoutaEvRideFactory.deploy.selector,
            params
        );

        bytes32 structHash = keccak256(
            abi.encode(
                FORWARD_REQUEST_TYPEHASH,
                from,
                to,
                value,
                gas,
                nonce,
                deadline,
                keccak256(data)
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
                ),
                keccak256('RoutaEvCustomForwarder'),
                keccak256('1'),
                block.chainid,
                address(forwarder)
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked('\x19\x01', domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(team);
        forwarder.execute(
            ERC2771Forwarder.ForwardRequestData({
                to: to,
                from: from,
                value: value,
                gas: gas,
                deadline: deadline,
                data: data,
                signature: signature
            })
        );

        assertEq(factory.allRidesLength(), 1);
    }

    function runRiderFulfillment() public {
        string memory message = 'RoutaEv:fulfill';
        bytes32 actionMessageHash = MessageHashUtils.toEthSignedMessageHash(
            message.generateHash()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(driverPk, actionMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Let the driver sign first
        address from = driver;
        address to = factory.offChainReference(offChainReference);
        uint256 value = 0;
        uint256 gas = 1000000;
        uint256 nonce = forwarder.nonces(from);
        uint48 deadline = uint48(block.timestamp + 1 days);
        bytes memory data = abi.encodeWithSelector(
            IRoutaEvRide.fulfill.selector,
            signature
        );

        bytes32 structHash = keccak256(
            abi.encode(
                FORWARD_REQUEST_TYPEHASH,
                from,
                to,
                value,
                gas,
                nonce,
                deadline,
                keccak256(data)
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
                ),
                keccak256('RoutaEvCustomForwarder'),
                keccak256('1'),
                block.chainid,
                address(forwarder)
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked('\x19\x01', domainSeparator, structHash)
        );

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(driverPk, digest);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        vm.prank(team);
        forwarder.execute(
            ERC2771Forwarder.ForwardRequestData({
                to: to,
                from: from,
                value: value,
                gas: gas,
                deadline: deadline,
                data: data,
                signature: signature1
            })
        );

        assertTrue(true);
    }

    function runPayerFulfillment() public {
        string memory message = 'RoutaEv:fulfill';
        bytes32 actionMessageHash = MessageHashUtils.toEthSignedMessageHash(
            message.generateHash()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, actionMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Let the payer sign next
        address from = payer;
        address to = factory.offChainReference(offChainReference);
        uint256 value = 0;
        uint256 gas = 1000000;
        uint256 nonce = forwarder.nonces(from);
        uint48 deadline = uint48(block.timestamp + 1 days);
        bytes memory data = abi.encodeWithSelector(
            IRoutaEvRide.fulfill.selector,
            signature
        );

        bytes32 structHash = keccak256(
            abi.encode(
                FORWARD_REQUEST_TYPEHASH,
                from,
                to,
                value,
                gas,
                nonce,
                deadline,
                keccak256(data)
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
                ),
                keccak256('RoutaEvCustomForwarder'),
                keccak256('1'),
                block.chainid,
                address(forwarder)
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked('\x19\x01', domainSeparator, structHash)
        );

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(payerPk, digest);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        vm.prank(team);
        forwarder.execute(
            ERC2771Forwarder.ForwardRequestData({
                to: to,
                from: from,
                value: value,
                gas: gas,
                deadline: deadline,
                data: data,
                signature: signature1
            })
        );

        IRoutaEvRide.Status status = IRoutaEvRide(to).status();
        assert(status == IRoutaEvRide.Status.COMPLETED);
    }

    function test_all() public {
        runDeploymentTest();
        runRiderFulfillment();
        runPayerFulfillment();
    }
}
