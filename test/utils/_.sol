pragma solidity >=0.8.28;

library Utils {
    function generateHash(
        string memory message
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(message));
    }
}
