//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct APY {
        uint256 percentage; // APY in percentage
        uint256 duration; // Duration in days
    }

    // Deposit Item
    struct DepositDetails {
        APY apy;
        uint256 amount; // Amount of staked tokens
        uint256 timestamp; // Deposit creation timestamp
    }

    // Info of each user.
    struct UserInfo {
        uint256 totalStakedAmount; // How many tokens the user has provided.
        DepositDetails[] deposits; // Deposited list
    }

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public startedTimestamp;
    uint256 public totalStaked;
    uint256 public exitPenaltyPercentage;
    uint256 public withdrawFee;

    mapping (address => UserInfo) private userInfo;
    mapping (uint256 => uint256) private apyOptions; // maps duration in Days to the APY percentage
    uint256[] private apyDurations;

    /* ------------- EVENTS ------------- */

    event Deposit(address indexed user, uint256 amount, uint256 index);
    event Withdraw(address indexed user, uint256 amount);
    event StakingReward(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    /* ------------- CONSTRUCTOR ------------- */

    constructor(
        address _tokenAddress,
        uint256 _apyPercentage,
        uint256 _apyDuration,
        uint256 _exitPenaltyPercentage,
        uint256 _withdrawFee
    ) Ownable(msg.sender) {
        stakingToken = IERC20(_tokenAddress);
        rewardToken = stakingToken;

        apyOptions[_apyDuration] = _apyPercentage;
        apyDurations.push(_apyDuration);
        exitPenaltyPercentage = _exitPenaltyPercentage;
        withdrawFee = _withdrawFee;

        startedTimestamp = block.timestamp;
        totalStaked = 0;
    }

    /* ------------- STAKING/UNSTAKING ------------- */

    /**
     * @notice Allows a user to stake a specified amount of tokens with a given staking option (APY).
     * @dev This function is protected against reentrancy attacks.
     * @param _amount The amount of tokens to stake.
     * @param _duration The duration of the staking period.
     * @notice The user must call the `approve` method of the ERC20 token on the `stakingToken` before calling this function.
     */
    function stake(uint256 _amount, uint256 _duration, address _stakeholder) public whenNotPaused nonReentrant {
        require(apyDurations.length > 0, "There are no available APY options");
        require(_amount > 0, "Invalid Amount");
        require(apyOptions[_duration] > 0, "Invalid duration");

        UserInfo storage user = userInfo[_stakeholder];
        uint256 initialBalance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 amountTransferred = stakingToken.balanceOf(address(this)) - initialBalance;
        require(amountTransferred <= _amount, "Transfer amount exceeds expected");

        user.totalStakedAmount += amountTransferred;
        totalStaked += amountTransferred;
        APY memory currentApy = APY({
            percentage: apyOptions[_duration],
            duration: _duration
        });
        // Create a new DepositDetails instance
        DepositDetails memory newDeposit = DepositDetails({
            apy: currentApy,
            amount: amountTransferred,
            timestamp: block.timestamp
        });

        // Get the index before pushing
        uint256 index = user.deposits.length;
        user.deposits.push(newDeposit);
        emit Deposit(_stakeholder, amountTransferred, index);
    }

    function unstakeAllDeposits() public whenNotPaused nonReentrant {
        _unstakeAllDeposits(msg.sender);
    }

    /**
     * @notice Allows a user to unstake their staked tokens plus available reward.
     * @dev This function is protected by the nonReentrant modifier to prevent reentrancy attacks.
     * @param _index The index of the deposit to be unstaked.
     */
    function unstakeByIndex(uint256 _index) public whenNotPaused nonReentrant {
        _unstakeByIndex(msg.sender, _index);
    }

    function _unstakeByUserAndIndex(address _user, uint256 _index) internal returns (uint256, uint256) {
        require(startedTimestamp > 0, "Not started yet");
        UserInfo storage user = userInfo[_user];
        require(_index < user.deposits.length, "Index out of bound");
        uint256 depositAmount = user.deposits[_index].amount;
        uint256 amount = user.deposits[_index].amount;

        uint256 elapsedTime;
        uint256 stakingReward = 0;
        if (startedTimestamp > user.deposits[_index].timestamp) {
            elapsedTime = block.timestamp - startedTimestamp;
        } else {
            elapsedTime = block.timestamp - user.deposits[_index].timestamp;
        }

        if (elapsedTime < user.deposits[_index].apy.duration) {
            // Early withdraw
            amount -= amount * exitPenaltyPercentage / 100;
            if (amount > 0) {
                emit EmergencyWithdraw(_user, amount);
            }
        } else {
            // Normal Withdraw
            uint256 fee = amount * withdrawFee / 100;
            // Send Amount + Reward to user
            amount -= fee;
            stakingReward = _calculateReward(_user, _index);
            amount += stakingReward;
            if (amount > 0) {
                emit Withdraw(_user, amount);
            }
        }

        user.totalStakedAmount -= depositAmount;
        totalStaked -= depositAmount;

        return (stakingReward, amount);
    }

    function _unstakeAllDeposits(address _stakeholder) internal {
        require(startedTimestamp > 0, "Not started yet");
        UserInfo storage user = userInfo[_stakeholder];
        uint256 treasuryBalance = rewardToken.balanceOf(address(this));
        uint256 totalStakingReward = 0;
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < user.deposits.length; i++) {
            (uint256 stakingReward, uint256 amount) = _unstakeByUserAndIndex(_stakeholder, i);
            totalStakingReward += stakingReward;
            totalAmount += amount;
        }
        require(totalAmount <= treasuryBalance, "Insufficient treasury balance");
        // Clear deposits
        while (user.deposits.length > 0) {
            user.deposits.pop();
        }
        if (totalAmount > 0) {
            stakingToken.safeTransfer(address(_stakeholder), totalAmount);
        }

        emit StakingReward(_stakeholder, totalStakingReward);
    }

    function _unstakeByIndex(address _stakeholder, uint256 _index) internal {
        UserInfo storage user = userInfo[_stakeholder];
        uint256 treasuryBalance = rewardToken.balanceOf(address(this));
        (uint256 stakingReward, uint256 amount) = _unstakeByUserAndIndex(_stakeholder, _index);
        require(amount <= treasuryBalance, "Insufficient treasury balance");

        // Remove deposit item
        for (uint256 i = _index; i < user.deposits.length - 1; i++) {
            user.deposits[i] = user.deposits[i + 1];
        }
        user.deposits.pop();

        if (amount > 0) {
            stakingToken.safeTransfer(address(_stakeholder), amount);
        }

        emit StakingReward(_stakeholder, stakingReward);
    }

    function _calculateReward(address _user, uint256 _index) internal view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        require(_index < user.deposits.length, "Index out of bound");
        if (startedTimestamp == 0 || user.totalStakedAmount == 0) {
            return 0;
        }
        
        uint256 elapsedTime;
        if (startedTimestamp > user.deposits[_index].timestamp) {
            elapsedTime = block.timestamp - startedTimestamp;
        } else {
            elapsedTime = block.timestamp - user.deposits[_index].timestamp;
        }
        
        if (elapsedTime > user.deposits[_index].apy.duration) {
            elapsedTime = user.deposits[_index].apy.duration;
        }
        
        return (user.deposits[_index].amount * elapsedTime) * user.deposits[_index].apy.percentage / 100 / 365 days;
    }

    /* ------------- CONTRACT MANAGEMENT ------------- */

    function startReward() external onlyOwner {
        require(startedTimestamp == 0, "Can only start rewards once");
        startedTimestamp = block.timestamp;
        _unpause();
    }

    function stopReward() external onlyOwner {
        startedTimestamp = 0;
        _pause();
    }

    function rewardsRemaining() public view returns (uint256) {
        uint256 reward = rewardToken.balanceOf(address(this));
        if (reward > totalStaked) {
            reward -= totalStaked;
        } else {
            reward = 0;
        }

        return reward;
    }

    function reset() external onlyOwner {
        uint256 balance = rewardToken.balanceOf(address(this));
        rewardToken.safeTransfer(address(msg.sender), balance);
        totalStaked = 0;
    }

    function adminUnstakeAllDeposits(address _stakeholder) public onlyOwner whenNotPaused nonReentrant {
        _unstakeAllDeposits(_stakeholder);
    }

    function adminUnstakeByIndex(address _stakeholder, uint256 _index) public onlyOwner whenNotPaused nonReentrant {
        _unstakeByIndex(_stakeholder, _index);
    }

    // Withdraw reward. EMERGENCY ONLY. This allows the owner to migrate rewards to a new staking pool since we are not minting new tokens.
    function withdrawEmergencyReward(uint256 _amount) external onlyOwner {
        require(_amount <= rewardToken.balanceOf(address(this)) - totalStaked, 'not enough tokens to take out');
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    function addOrUpdateApyOption(uint256 _percentage, uint256 _duration) external onlyOwner {
        require(_percentage <= 10000, "APY must be below 10000%");
        if (apyOptions[_duration] == 0) {
            apyDurations.push(_duration);
        }
        apyOptions[_duration] = _percentage;
    }

    function deleteApyOption(uint256 _duration) external onlyOwner {
        // Find and remove the duration from the array
        for (uint256 i = 0; i < apyDurations.length; i++) {
            if (apyDurations[i] == _duration) {
                for (uint256 j = i; j < apyDurations.length - 1; j++) {
                    apyDurations[j] = apyDurations[j + 1];
                }
                apyDurations.pop();
                break;
            }
        }

        // Remove the APY option
        delete apyOptions[_duration];
    }

    function updateExitPenalty(uint256 _exitPenaltyPercentage) external onlyOwner {
        require(_exitPenaltyPercentage <= 50, "May not set higher than 50%");
        exitPenaltyPercentage = _exitPenaltyPercentage;
    }

    function updateFee(uint256 newWithdrawFee) external onlyOwner {
        withdrawFee = newWithdrawFee;
    }

    /* ------------- PUBLIC DETAILS ------------- */

    function getApyDurations() external view returns (uint256[] memory) {
        return apyDurations;
    }

    function getApyByDuration(uint256 _duration) external view returns (uint256) {
        return apyOptions[_duration];
    }

    function getApyOptionsLength() external view returns (uint256) {
        return apyDurations.length;
    }

    function getStakedTokens(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        return user.totalStakedAmount;
    }

    function getStakedItemLength(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        return user.deposits.length;
    }

    function getAPYs() external view returns (APY[] memory) {
        APY[] memory values = new APY[](apyDurations.length);
        for (uint256 i = 0; i < apyDurations.length; i++) {
            uint256 _duration = apyDurations[i];
            uint256 _percentage = apyOptions[_duration];
            values[i] = APY({
                percentage: _percentage,
                duration: _duration
            });
        }

        return values;
    }

    function getDeposits(address _user) external view returns (DepositDetails[] memory) {
        UserInfo memory user = userInfo[_user];
        return user.deposits;
    }

    function getDepositByIndex(address _user, uint256 _index) external view returns (DepositDetails memory) {
        UserInfo memory user = userInfo[_user];
        require(_index < user.deposits.length, "Index out of bound");
        return user.deposits[_index];
    }

    function getDepositAPY(address _user, uint256 _index) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        require(_index < user.deposits.length, "Index out of bound");
        return user.deposits[_index].apy.percentage;
    }

    function getDepositDuration(address _user, uint256 _index) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        require(_index < user.deposits.length, "Index out of bound");
        return user.deposits[_index].apy.duration;
    }

    function getDepositAmount(address _user, uint256 _index) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        require(_index < user.deposits.length, "Index out of bound");
        return user.deposits[_index].amount;
    }

    function getDepositReward(address _user, uint256 _index) external view returns (uint256) {
        return _calculateReward(_user, _index);
    }

    function getStakingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 reward = 0;
        for (uint256 i = 0; i < user.deposits.length; i++) {
            uint256 depositReward = _calculateReward(_user, i);
            reward += depositReward;
        }

        return reward;
    }

    function getDepositTimestamp(address _user, uint256 _index) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        require(_index < user.deposits.length, "Index out of bound");

        if (startedTimestamp > user.deposits[_index].timestamp) {
            return startedTimestamp;
        }

        return user.deposits[_index].timestamp;
    }

    function getDepositElapsed(address _user, uint256 _index) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        require(_index < user.deposits.length, "Index out of bound");

        uint256 depositTimestamp = user.deposits[_index].timestamp;
        if (startedTimestamp > depositTimestamp) {
            depositTimestamp = startedTimestamp;
        }

        return block.timestamp - depositTimestamp;
    }
}
