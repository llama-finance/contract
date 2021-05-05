// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IController.sol";

contract LMVault is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;

    uint public min = 10000;
    uint public constant max = 10000;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    bool public allowContract = false;

    bool public earnImmediately;

    address public governance;
    address public controller;

    constructor (address _token, address _controller, bool _earnImmediately) ERC20(
        string(abi.encodePacked("lm", ERC20(_token).name())),
        string(abi.encodePacked("lm", ERC20(_token).symbol()))
    ) {
        _setupDecimals(ERC20(_token).decimals());
        token = IERC20(_token);
        governance = msg.sender;
        controller = _controller;
        earnImmediately = _earnImmediately;
    }

    modifier onlyHuman {
        if (!allowContract) {
            require(msg.sender == tx.origin);
            _;
        }
    }

    function balance() public view returns (uint) {
        return token.balanceOf(address(this))
        .add(IController(controller).balanceOf(address(token)));
    }

    function setMin(uint _min) external {
        require(msg.sender == governance, "!governance");
        min = _min;
    }

    function toggleAllowContract(bool _b) public {
        require(msg.sender == governance, "!governance");
        allowContract = _b;
    }

    function toggleEarnImmediately(bool _b) public {
        require(msg.sender == governance, "!governance");
        earnImmediately = _b;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function available() public view returns (uint) {
        return token.balanceOf(address(this)).mul(min).div(max);
    }

    function earn() public {
        uint _bal = available();
        token.safeTransfer(controller, _bal);
        IController(controller).earn(address(token), _bal);
    }

    function depositAll() external onlyHuman {
        deposit(token.balanceOf(msg.sender));
    }

    function deposit(uint _amount) public payable onlyHuman {
        if (msg.value > 0) {
            require(address(token) == WBNB, "!bnb");
            require(_amount == msg.value);
        } else {
            require(msg.value == 0);
        }

        uint _pool = balance();
        uint _before = token.balanceOf(address(this));
        if (msg.value > 0) {
            IWETH(WBNB).deposit{value: msg.value}();
        } else {
            token.safeTransferFrom(msg.sender, address(this), _amount);
        }
        uint _after = token.balanceOf(address(this));
        _amount = _after.sub(_before);
        uint shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
        if (earnImmediately) {
            earn();
        }
    }

    function withdrawAll() external onlyHuman {
        withdraw(balanceOf(msg.sender));
    }

    function withdraw(uint _shares) public onlyHuman {
        uint r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        uint b = token.balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b);
            IController(controller).withdraw(address(token), _withdraw);
            uint _after = token.balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        if (address(token) == WBNB) {
            IWETH(WBNB).withdraw(r);
            Address.sendValue(msg.sender,r);
        } else {
            token.safeTransfer(msg.sender, r);
        }
    }

    function getPricePerFullShare() public view returns (uint) {
        if (totalSupply() == 0) {
            return 1e18;
        }
        return balance().mul(1e18).div(totalSupply());
    }
    receive() payable external {}
}
