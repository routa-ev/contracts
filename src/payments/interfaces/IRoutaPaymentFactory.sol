pragma solidity >=0.8.28;

interface IRoutaPaymentFactory {
    struct DeploymentParams {
        address _receiver;
        address[] _tokens;
        string _offChainSlug;
    }

    function deploy(DeploymentParams memory _params) external returns (address);
}
