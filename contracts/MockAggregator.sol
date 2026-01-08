// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockAggregator {
    int256 private answer;
    uint8 private _decimals;

    constructor(int256 _answer, uint8 decimals_) {
        answer = _answer;
        _decimals = decimals_;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        return (0, answer, 0, 0, 0);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}
