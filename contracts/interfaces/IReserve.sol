pragma solidity ^0.8.30;

interface IReserve {
    /**
     * @notice return this pool reserve backing.
     * @dev that in Principal Token and Swap Token this will return the associated swapToken id/epoch reserve
     * e.g if the Principal Token epoch/swapToken id is 2 but the newest swapToken id/epoch is 4
     * this will still return backing reserve for swapToken id/epoch 2
     * for LV tokens, this will always return the current backing reserve
     * @return collateralAsset The Collateral Asset reserve amount for share contract.
     * @return referenceAsset The Reference Asset reserve amount for share contract.
     */
    function getReserves() external view returns (uint256 collateralAsset, uint256 referenceAsset);
}
