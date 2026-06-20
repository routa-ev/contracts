pragma solidity >=0.8.28;

interface IRoutaPaymentChannel {
    error AlreadyInitialized();
    error NotEnoughBalance();
    error AlreadyDrained();
    error AlreadyReleased();
    error AlreadyRevoked();
    error AlreadyRefunded();
    error CannotRefund();
    error UsePayNative();
    error TokenNotAllowed();
    error ReferenceAlreadyUsed();
    error OnlyPayer();
    error NotReleased();
    error ChannelNotActive();
    error ChannelAlreadyActive();
    error Deadline();
    error OnlyTeam();

    struct Payment {
        address _token;
        uint256 _amount;
        address _payer;
        bool _released;
        bool _revoked;
        bool _refunded;
        uint256 _createdAt;
        string _memo;
    }

    enum ChannelStatus {
        Active,
        Closed
    }

    event Initialized(
        address[] _paymentTokens,
        address indexed _owner,
        address indexed _receiver,
        string _offChainSlug,
        uint256 _timestamp
    );
    event NewPayment(
        bytes32 indexed _paymentId,
        address indexed _payer,
        address indexed _token,
        uint256 _amount,
        string _memo,
        uint256 _timestamp
    );
    event ReleasePayment(bytes32 indexed _paymentId, uint256 _timestamp);
    event RevokePayment(bytes32 indexed _paymentId, uint256 _timestamp);
    event RefundPayment(bytes32 indexed _paymentId, uint256 _timestamp);
    event EmergencyReleasePayment(
        bytes32 indexed _paymentId,
        uint256 _timestamp
    );
    event Payout(
        bytes32 indexed _paymentId,
        address indexed _token,
        address indexed _receiver,
        uint256 _amount,
        uint256 _timestamp
    );

    /// @notice Initializes the payment channel with the given payment tokens, receiver, and off-chain slug.
    /// @param _paymentTokens The list of payment tokens supported by this channel.
    /// @param _owner The address of the owner of this channel.
    /// @param _receiver The address of the recipient of all payments made through this channel.
    /// @param _offChainSlug The off-chain slug that identifies this payment channel.
    function initialize(
        address[] memory _paymentTokens,
        address _owner,
        address _receiver,
        string memory _offChainSlug
    ) external;

    /// @notice Claims the payment with the given payment ID and amount. Can only be called by the contract owner.
    /// @param _paymentId The ID of the payment to claim.
    /// @param _amount The amount to claim.
    function claim(bytes32 _paymentId, uint256 _amount) external;

    /// @notice Releases the payment with the given payment ID. Can only be called by the payer.
    /// @param _paymentId The ID of the payment to release.
    function releasePayment(bytes32 _paymentId) external;

    /// @notice Refunds the payment with the given payment ID. Can only be called by the contract owner.
    /// @param _paymentId The ID of the payment to refund.
    function refundPayment(bytes32 _paymentId) external;

    /// @notice Revokes the payment with the given payment ID. Can only be called by the payer. Would fail if the payment is already released or revoked.
    /// @param _paymentId The ID of the payment to revoke.
    function revokePayment(bytes32 _paymentId) external;

    /// @notice Pays with ERC20 token. Would internally check if the token is supported before paying.
    /// @param _token The address of the ERC20 token to pay with.
    /// @param _amount The amount to pay.
    /// @param _data Concatenation of the payer's permit signature, a memo, an off-chain reference, a boolean indicating whether to release the payment immediately, and a deadline.
    function payWithERC20(
        address _token,
        uint256 _amount,
        bytes memory _data
    ) external returns (bytes32 _paymentId);

    /// @notice Pays with native token (i.e. ETH). Would internally check if the token is supported before paying.
    /// @param _amount The amount to pay.
    /// @param _data Concatenation of a memo, an off-chain reference, a boolean indicating whether to release the payment immediately, and a deadline.
    function payWithNative(
        uint256 _amount,
        bytes memory _data
    ) external payable returns (bytes32 _paymentId);

    /// @notice Emergency release of a payment. Can only be called by the team.
    /// @param _paymentId The ID of the payment to release.
    /// @param _receiver The address to release the payment to.
    function emergencyRelease(bytes32 _paymentId, address _receiver) external;

    /// @notice Closes the payment channel.
    function close() external;

    /// @notice Activates the payment channel.
    function activate() external;

    /// @notice Returns the address of the factory contract.
    function factory() external view returns (address);

    /// @notice Returns the address of the payment token at the given index.
    /// @param index The index of the payment token to return.
    function paymentTokens(uint256 index) external view returns (address);

    /// @notice Returns the off-chain reference for the given payment ID.
    function paymentOffChainReference(
        bytes32 _paymentId
    ) external view returns (string memory);

    /// @notice Returns the payment ID for the given off-chain reference.
    function paymentIdFromOffChainReference(
        string memory _reference
    ) external view returns (bytes32);

    /// @notice Returns the number of payment tokens.
    function paymentTokensLength() external view returns (uint256);

    /// @notice Returns the address of the receiver.
    function receiver() external view returns (address);

    /// @notice Returns the off-chain slug.
    function offChainSlug() external view returns (string memory);

    /// @notice Returns the payment details for the given payment ID.
    /// @param _paymentId The ID of the payment to return details for.
    function getPayment(
        bytes32 _paymentId
    )
        external
        view
        returns (
            address,
            uint256,
            address,
            bool,
            bool,
            bool,
            uint256,
            string memory
        );

    /// @notice Returns the status of the payment channel.
    function status() external view returns (ChannelStatus);

    /// @notice Returns the address of the native token (ETH).
    function ETHER() external view returns (address);
}
