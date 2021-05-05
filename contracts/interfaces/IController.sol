// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

interface IController {
    function withdraw(address, uint) external;
    function balanceOf(address) external view returns (uint);
    function earn(address, uint) external;
    function vaults(address) external returns (address);
    function rewards() external returns (address);
}
