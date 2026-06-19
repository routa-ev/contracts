pragma solidity >=0.8.28;

interface IRoutaPaymentChannel {
    struct Payment {
        address token;
        uint256 amount;
        address payer;
        bool released;
        uint256 createdAt;
        string memo;
    }

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

    /// @notice Pays with ERC20 token. Would internally check if the token is supported before paying.
    /// @param _token The address of the ERC20 token to pay with.
    /// @param _amount The amount to pay.
    /// @param _data Concatenation of the payer's permit signature, a memo, and a boolean indicating whether to release the payment immediately.
    function payWithERC20(
        address _token,
        uint256 _amount,
        bytes memory _data
    ) external returns (bytes32 _paymentId);

    /// @notice Pays with native token (i.e. ETH). Would internally check if the token is supported before paying.
    /// @param _amount The amount to pay.
    /// @param _data Concatenation of a memo, and a boolean indicating whether to release the payment immediately.
    function payWithNative(
        uint256 _amount,
        bytes memory _data
    ) external payable returns (bytes32 _paymentId);

    /// @notice Returns the address of the factory contract.
    function factory() external view returns (address);

    /// @notice Returns the address of the payment token at the given index.
    /// @param index The index of the payment token to return.
    function paymentTokens(uint256 index) external view returns (address);

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
        returns (address, uint256, address, bool, uint256, string memory);
}
