pragma solidity >=0.8.28;

import {console} from 'forge-std/console.sol';
import {Test} from 'forge-std/Test.sol';
import {IRoutaPaymentChannel} from '../src/payments/interfaces/IRoutaPaymentChannel.sol';
import {IRoutaPaymentFactory} from '../src/payments/interfaces/IRoutaPaymentFactory.sol';
import {RoutaPaymentChannel} from '../src/payments/RoutaPaymentChannel.sol';
import {RoutaPaymentFactory} from '../src/payments/factories/RoutaPaymentFactory.sol';
import {ROUTA} from '../src/ROUTA.sol';
import {RoutaCustomForwarder} from '../src/RoutaCustomForwarder.sol';
import {ERC2771Forwarder} from '@openzeppelin/contracts/metatx/ERC2771Forwarder.sol';

contract PaymentsTest is Test {
    ROUTA public routa;
    RoutaPaymentFactory public factory;
    RoutaCustomForwarder public forwarder;

    uint256 private teamPk = 0xD0E;
    uint256 private payerPk = 0xA11CE;
    uint256 private ownerPk = 0xB0B;
    uint256 private receiverPk = 0xC0C;

    address private team;
    address private payer;
    address private channelOwner;
    address private receiver;

    string private offChainSlug;

    bytes32 internal constant FORWARD_REQUEST_TYPEHASH =
        keccak256(
            'ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)'
        );

    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256(
            'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
        );

    function setUp() public {
        initParams();
        RoutaPaymentChannel channelImpl = new RoutaPaymentChannel(
            address(forwarder)
        );
        factory = new RoutaPaymentFactory(
            address(channelImpl),
            address(forwarder),
            team
        );
    }

    function initParams() public {
        team = vm.addr(teamPk);
        payer = vm.addr(payerPk);
        channelOwner = vm.addr(ownerPk);
        receiver = vm.addr(receiverPk);

        offChainSlug = string(
            abi.encodePacked('PAY-', vm.toString(block.timestamp))
        );

        forwarder = new RoutaCustomForwarder(team);

        routa = new ROUTA();
        routa.setMinter(team);

        vm.prank(team);
        routa.mint(payer, 170000000 ether);
    }

    function deployPaymentChannel() public {
        vm.prank(channelOwner);

        address[] memory tokens = new address[](1);
        tokens[0] = address(routa);

        address from = channelOwner;
        address to = address(factory);
        uint256 value = 0;
        uint256 gas = 1000000;
        uint256 nonce = forwarder.nonces(from);
        uint48 deadline = uint48(block.timestamp + 1 days);

        IRoutaPaymentFactory.DeploymentParams
            memory params = IRoutaPaymentFactory.DeploymentParams({
                _offChainSlug: offChainSlug,
                _receiver: receiver,
                _tokens: tokens
            });

        bytes memory data = abi.encodeWithSelector(
            IRoutaPaymentFactory.deploy.selector,
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
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

        assertEq(factory.allPaymentChannelsLength(), 1);
    }

    function createERC20Permit(
        address channel
    ) public view returns (bytes memory) {
        uint256 deadline = block.timestamp + 1 days;

        // Sign permit message
        uint256 nonce = routa.nonces(payer);
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                payer,
                channel,
                3 ether,
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
        return sig;
    }

    function executePaymentWithERC20() public {
        address from = payer;
        address to = factory.offChainSlugToPaymentChannel(offChainSlug);
        uint256 value = 0;
        uint256 gas = 1000000;
        uint256 nonce = forwarder.nonces(from);
        uint48 deadline = uint48(block.timestamp + 1 days);
        string memory _memo = 'This is just a test payment';
        string memory _reference = string(
            abi.encodePacked('PayRef-', block.timestamp)
        );

        bytes memory _internalData = abi.encode(
            createERC20Permit(to),
            _memo,
            _reference,
            false,
            deadline
        );

        bytes memory data = abi.encodeWithSelector(
            IRoutaPaymentChannel.payWithERC20.selector,
            address(routa),
            3 ether,
            _internalData
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

        uint256 amount = 3 ether;
        uint256 fee = (factory.FEE() * amount) / 10000;

        assertEq(IRoutaPaymentChannel(to).paymentsLength(), 1);
        assertEq(routa.balanceOf(to), amount - fee);
    }

    function executePaymentRelease() public {
        address from = payer;
        address to = factory.offChainSlugToPaymentChannel(offChainSlug);
        uint256 value = 0;
        uint256 gas = 1000000;
        uint256 nonce = forwarder.nonces(from);
        uint48 deadline = uint48(block.timestamp + 1 days);
        bytes32 paymentId = IRoutaPaymentChannel(to).payments(0);

        bytes memory data = abi.encodeWithSelector(
            IRoutaPaymentChannel.releasePayment.selector,
            paymentId
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

        (, , , bool _released, , , , ) = IRoutaPaymentChannel(to).getPayment(
            paymentId
        );

        assertTrue(_released);
    }

    function executePaymentClaim() public {
        address from = channelOwner;
        address to = factory.offChainSlugToPaymentChannel(offChainSlug);
        uint256 value = 0;
        uint256 gas = 1000000;
        uint256 nonce = forwarder.nonces(from);
        uint48 deadline = uint48(block.timestamp + 1 days);
        bytes32 paymentId = IRoutaPaymentChannel(to).payments(0);

        uint256 receiverBalanceBefore = routa.balanceOf(receiver);

        bytes memory data = abi.encodeWithSelector(
            IRoutaPaymentChannel.claim.selector,
            paymentId,
            routa.balanceOf(to)
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
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

        uint256 receiverBalanceAfter = routa.balanceOf(receiver);
        assertTrue(receiverBalanceAfter > receiverBalanceBefore);
    }

    function test_all() public {
        deployPaymentChannel();
        executePaymentWithERC20();
        executePaymentRelease();
        executePaymentClaim();
    }
}
