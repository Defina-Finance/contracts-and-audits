// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "./FinaFarming.sol";

contract FinaLockFarming is Initializable, OwnableUpgradeable, FinaFarming {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint[] public depositTier; //requirements for deposit lock
    uint[] public rewardRatioByTier; //need to divide by 10000

    event Rewards(address who, uint pid, uint rewardOne, uint rewardTwo);
    event DepositTier(uint[] value);
    event RewardRatioByTier(uint[] value);

    constructor() {}

    function initialize(IERC20Upgradeable finaToken_, IERC20Upgradeable secondToken_, address devAddr_,
        uint rewardPerBlock_, uint startBlock_) external virtual override initializer {
        __FinaFarming_init(finaToken_, secondToken_, devAddr_, rewardPerBlock_, startBlock_);
        depositTier = [30 days, 60 days, 90 days, 120 days];
        rewardRatioByTier = [1000, 2000, 4000, 7500];
    }

    function depositLP(uint _pid, uint _amount) external virtual override onlyEOA whenNotPaused {
        require(_amount>0, "deposit amount is null");
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        UserLPInfo storage user = userLPInfo[_pid][_msgSender()];
        updateLPPool(_pid);
        if (user.amount > 0) {
            //use weight(amount) averaged time
            user.averageDepositedTime =
            (user.averageDepositedTime * user.amount + _amount * block.timestamp) / (user.amount + _amount);

        } else {
            user.firstDepositedTime = block.timestamp;
            user.averageDepositedTime = user.firstDepositedTime;
        }
        lpPool.lpToken.safeTransferFrom(address(_msgSender()), address(this), _amount);
        user.amount += _amount;
        user.rewardDebt = user.amount * lpPool.accRewardPerShare / 1e12;
        emit Deposit(_msgSender(), _pid, _amount);
    }

    //front end function to return the "current" expected rewards
    function pendingLPRewardByTier(uint _pid, address _user) public view returns (uint[] memory pending_) {
        uint[] memory p = pendingLPReward(_pid,_user);
        uint pending = p[0];
        uint pendingExtra = p[1];
        if(pending > 0){
            for(uint i = depositTier.length - 1; i >= 0 ; i--) {
                if(block.timestamp>= userLPInfo[_pid][_user].averageDepositedTime + depositTier[i]){
                    p[0] = pending * rewardRatioByTier[i] / 10000;
                    p[1] = pendingExtra * rewardRatioByTier[i] / 10000;
                    break;
                } 
            }
        }
        return p;
    }

    //front end function to return the "current" tier for the user
    function currentUserTier(uint _pid, address _user) public view returns (uint x) {
        uint[] memory p = pendingLPReward(_pid,_user);
        uint pending = p[0];
        uint currentTier;
        if(pending > 0){
            for(uint i = depositTier.length - 1; i >= 0 ; i--) {
                if(block.timestamp>= userLPInfo[_pid][_user].averageDepositedTime + depositTier[i]){
                    currentTier = i;
                    break;
                } else {
                    currentTier = 0;
                }
            }
        }
        return currentTier;
    }

    function withdrawLP(uint _pid, uint _amount) external virtual override onlyEOA whenNotPaused {
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        UserLPInfo storage user = userLPInfo[_pid][_msgSender()];
        require(user.amount >= _amount, "withdraw amount overflow");
        updateLPPool(_pid);
        uint[] memory p = pendingLPReward(_pid,_msgSender());
        uint pending = p[0];
        uint pendingExtra = p[1];

        if(pending > 0){
            for(uint i = depositTier.length - 1; i >= 0 ; i--) {
                if(block.timestamp>= user.averageDepositedTime + depositTier[i]){
                    p[0] = pending * rewardRatioByTier[i] / 10000;
                    p[1] = pendingExtra * rewardRatioByTier[i] / 10000;
                    break;
                } 
            }
            finaToken.safeTransfer(_msgSender(), p[0]);
            secondRewardToken.safeTransfer(_msgSender(), p[1]);
            emit Rewards(_msgSender(), _pid, p[0], p[1]);
        }

        if(_amount > 0) {
            lpPool.lpToken.safeTransfer(address(_msgSender()), _amount);
            if(_amount < user.amount) {
                //if not all withdrawn, update averageDepositedTime
                user.averageDepositedTime = (user.averageDepositedTime * user.amount - _amount * block.timestamp) / (user.amount - _amount);
            }
            user.amount = user.amount - _amount;
        } else {
            //reset averageDepositedTime if _amount=0, i.e. only claim rewards
            user.averageDepositedTime = block.timestamp;
        }
        if(user.amount == 0) {
            //if all withdrawn, reset timer
            user.averageDepositedTime = 0;
            user.firstDepositedTime = 0;
        }
        user.rewardDebt = user.amount * lpPool.accRewardPerShare / 1e12;
        emit Withdraw(_msgSender(), _pid, _amount);
    }

    function withdrawEmergency(uint _pid) external virtual onlyEOA whenNotPaused {
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        UserLPInfo storage user = userLPInfo[_pid][_msgSender()];
        require(user.amount >0, "withdraw zero amount");
        //no need to calculate rewards in emergency
        updateLPPool(_pid);
        lpPool.lpToken.safeTransfer(address(_msgSender()), user.amount);
        user.rewardDebt = user.amount * lpPool.accRewardPerShare / 1e12;
        emit Withdraw(_msgSender(), _pid, user.amount);
    }

    function setDepositTierAndRatio(uint[] calldata seconds_, uint[] calldata ratio_) onlyOwner public {
        require(seconds_.length >0, "array length is null!");
        require(seconds_.length == ratio_.length, "array length not equal!");
        uint x = depositTier.length;
        uint y = seconds_.length;
        for(uint i = 0; i < x; i++){
            depositTier.pop();
            rewardRatioByTier.pop();
        }
        for(uint i = 0; i < y - 1; i++){
            require(seconds_[i]<seconds_[i+1],"depositTier array must be in ascending order");
        }
        depositTier = seconds_;
        rewardRatioByTier = ratio_;
        emit DepositTier(depositTier);
        emit RewardRatioByTier(rewardRatioByTier);
    }

}
