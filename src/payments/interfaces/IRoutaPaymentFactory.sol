pragma solidity >=0.8.28;

interface IRoutaPaymentFactory {
    struct DeploymentParams {
        address _receiver;
        address[] _tokens;
        string _offChainSlug;
    }

    /// @notice Deploys a new payment channel using the provided parameters.
    function deploy(DeploymentParams memory _params) external returns (address);

    /// @notice Returns the address of the payment channel at the given index.
    function allPaymentChannels(uint256 index) external view returns (address);

    /// @notice Returns the total number of payment channels deployed.
    function allPaymentChannelsLength() external view returns (uint256);

    /// @notice Returns the payment channel address associated with the given off-chain slug.
    function offChainSlugToPaymentChannel(
        string memory _offChainSlug
    ) external view returns (address);
}
