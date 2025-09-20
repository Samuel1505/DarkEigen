// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDarkEigenAVS {
    function submitOrderMatchTask(
        address pool,
        address trader,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (bool approved);
}