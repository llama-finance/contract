// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IStrategy.sol";

contract SimpleController {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address public governance;
    address public strategist;
    
    mapping(address => address) public vaults;
    mapping(address => address) public strategies;
    
    constructor() {
        governance = msg.sender;
        strategist = msg.sender;
    }
    
    function setStrategist(address _strategist) public {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }
    
    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    function setVault(address _token, address _vault) public {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        require(vaults[_token] == address(0), "exist vault");
        require(IVault(_vault).token() == _token, "!vault");
        vaults[_token] = _vault;
    }
    
    function setStrategy(address _token, address _strategy) public {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        require(IStrategy(_strategy).want() == _token, "!strategy");
        
        address _current = strategies[_token];
        if (_current != address(0)) {
           IStrategy(_current).withdrawAll();
        }
        strategies[_token] = _strategy;
    }
    
    function earn(address _token, uint _amount) public {
        address _strategy = strategies[_token];
        IERC20(_token).safeTransfer(_strategy, _amount);
        IStrategy(_strategy).deposit();
    }
    
    function balanceOf(address _token) external view returns (uint) {
        return IStrategy(strategies[_token]).balanceOf();
    }
    
    function withdrawAll(address _token) public {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        IStrategy(strategies[_token]).withdrawAll();
    }
    
    function inCaseTokensGetStuck(address _token, uint _amount) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
    
    function inCaseStrategyTokenGetStuck(address _strategy, address _token) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        IStrategy(_strategy).withdraw(_token);
    }
    
    function withdraw(address _token, uint _amount) public {
        require(msg.sender == vaults[_token], "!vault");
        IStrategy(strategies[_token]).withdraw(_amount);
    }

    function rewards() public view returns (address) {
        return governance;
    }
}