// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;
pragma abicoder v2;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./IAlpacaVault.sol";
import "./IFairLaunch.sol";
import "../../interfaces/IController.sol";
contract StrategyAlpacaSelf {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public strategistReward = 500;
    uint256 public withdrawalFee = 0;
    uint256 public constant FEE_DENOMINATOR = 10000;

    IAlpacaVault public AlpacaLend = IAlpacaVault(0xf1bE8ecC990cBcb90e166b71E368299f0116d421);
    IERC20 public ibAlpaca = IERC20(0xf1bE8ecC990cBcb90e166b71E368299f0116d421);
    IFairLaunch public AlpacaFairLaunch = IFairLaunch(0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F);
    uint256 public launchPoolID;
    address public RewardToken = 0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F;

    address public want; //alpaca token

    address public governance;
    address public controller;
    address public strategist;

    constructor(
        address _controller,
        address _want,
        uint256 _pid
    ) {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
        want = _want;
        launchPoolID = _pid;
    }

    function setStrategist(address _strategist) external {
        require(
            msg.sender == governance || msg.sender == strategist,
            "!authorized"
        );
        strategist = _strategist;
    }

    function setWithdrawalFee(uint256 _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }

    function setStrategistReward(uint256 _strategistReward) external {
        require(msg.sender == governance, "!governance");
        strategistReward = _strategistReward;
    }

    function e_exit() external {
        require(msg.sender == governance, "!governance");
        AlpacaFairLaunch.emergencyWithdraw(launchPoolID);
        AlpacaLend.withdraw(ibAlpaca.balanceOf(address(this)));
        uint balance = IERC20(want).balanceOf(address(this));
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        IERC20(want).safeTransfer(_vault, balance);
    }

    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(RewardToken != address(_asset), "want");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        _amount = _withdrawSome(_amount);

        uint256 _fee = _amount.mul(withdrawalFee).div(FEE_DENOMINATOR);

        if (_fee > 0) {
            IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
        }
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        if (_amount > _fee) {
            IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
        }
    }

    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));

        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        if (balance > 0) {
            IERC20(want).safeTransfer(_vault, balance);
        }
    }

    function _withdrawAll() internal {
        _withdrawSome(balanceOfPool());
    }

    modifier onlyBenevolent {
        require(
            msg.sender == tx.origin ||
            msg.sender == governance ||
            msg.sender == strategist
        );
        _;
    }

    //==================Real Logic================//

    function deposit() public {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(address(AlpacaLend), _want);
            uint256 before = ibAlpaca.balanceOf(address(this));
            AlpacaLend.deposit(_want);
            uint256 offset = ibAlpaca.balanceOf(address(this)).sub(before);
            ibAlpaca.safeApprove(address(AlpacaFairLaunch),offset);
            AlpacaFairLaunch.deposit(address(this),launchPoolID,offset);
        }
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 before;
        if (_amount > 0) {
            AlpacaFairLaunch.withdraw(address(this),launchPoolID, _amount.mul(balanceOfFairLaunch()).div(balanceOfPool()));
            before = IERC20(want).balanceOf(address(this));
            ibAlpaca.safeIncreaseAllowance(address(AlpacaLend),ibAlpaca.balanceOf(address(this)));
            AlpacaLend.withdraw(ibAlpaca.balanceOf(address(this)));
        }
        return IERC20(want).balanceOf(address(this)).sub(before);
    }

    function harvest() public onlyBenevolent {
        AlpacaFairLaunch.deposit(address(this),launchPoolID, 0);
        uint256 rewardAmt = IERC20(RewardToken).balanceOf(address(this));

        if (rewardAmt == 0) {
            return;
        }
        uint256 fee = rewardAmt.mul(strategistReward).div(FEE_DENOMINATOR);

        IERC20(RewardToken).safeTransfer(
            IController(controller).rewards(),
            fee
        );

        rewardAmt = IERC20(RewardToken).balanceOf(address(this));

        if (rewardAmt == 0) {
            return;
        }

        deposit();
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfFairLaunch() public view returns (uint256) {
        IFairLaunch.UserInfo memory info = AlpacaFairLaunch.userInfo(launchPoolID, address(this));
        return info.amount;
    }

    function balanceOfPool() public view returns (uint256) {
        IFairLaunch.UserInfo memory info = AlpacaFairLaunch.userInfo(launchPoolID, address(this));
        return info.amount.mul(AlpacaLend.totalToken()).div(AlpacaLend.totalSupply());
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfPool();
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}
