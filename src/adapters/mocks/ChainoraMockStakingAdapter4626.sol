// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IChainoraStakingAdapter} from "src/adapters/interfaces/IChainoraStakingAdapter.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {SafeTransferLibExt} from "src/libraries/SafeTransferLibExt.sol";

contract ChainoraMockStakingAdapter4626 is IChainoraStakingAdapter {
    using SafeTransferLibExt for address;

    address public immutable asset;
    uint256 public managedAssets;
    uint256 public pendingYield;

    constructor(address asset_) {
        asset = asset_;
    }

    function seedYield(uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        pendingYield += amount;
    }

    function depositIdle(uint256 assets) external returns (uint256 shares) {
        asset.safeTransferFrom(msg.sender, address(this), assets);
        managedAssets += assets;
        shares = assets;
    }

    function withdrawForLiquidity(uint256 assetsNeeded) external returns (uint256 assetsOut) {
        assetsOut = assetsNeeded;
        if (assetsOut > managedAssets) {
            assetsOut = managedAssets;
        }
        managedAssets -= assetsOut;
        asset.safeTransfer(msg.sender, assetsOut);
    }

    function totalManagedAssets() external view returns (uint256) {
        return managedAssets + pendingYield;
    }

    function harvestYield() external returns (uint256 yieldedAssets) {
        yieldedAssets = pendingYield;
        pendingYield = 0;
        managedAssets += yieldedAssets;
    }
}
