// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IChainoraStakingAdapter {
    function depositIdle(uint256 assets) external returns (uint256 shares);

    function withdrawForLiquidity(uint256 assetsNeeded) external returns (uint256 assetsOut);

    function totalManagedAssets() external view returns (uint256);

    function harvestYield() external returns (uint256 yieldedAssets);
}
