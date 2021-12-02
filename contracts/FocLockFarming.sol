// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

interface FocToken {
    function mint(address to, uint256 amount) external;
    function transferOwnership(address to) external;
}

contract FocLockFarming is Initializable, OwnableUpgradeable, PausableUpgradeable {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    FocToken public focToken;

    modifier onlyEOA() {
        require(_msgSender() == tx.origin, "FocFarming: not eoa");
        _;
    }

    struct UserLPInfo {
        uint amount;     // How many LP tokens the user has provided.
        uint rewardDebt; // pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
        uint firstDepositedTime; // keeps track of deposited time.
        uint averageDepositedTime; // use an average time for tier reward calculation.
    }

    struct LPPoolInfo {
        IERC20Upgradeable lpToken;           // Address of LP token contract.
        uint allocPoint;       // How many allocation points assigned to this pool. 
        uint lastRewardBlock;  // Last block number that reward distribution occurs.
        uint accRewardPerShare; // Accumulated rewards per share, times 1e12.
    }

    // Info of each LP pool.
    LPPoolInfo[] public lpPoolInfo;
    // Info of each user that stakes LP tokens. pid => {user address => UserLPInfo}
    mapping (uint => mapping (address => UserLPInfo)) public userLPInfo;

    uint public totalLPAllocPoint;
    uint public startBlock;
    uint public rewardPerBlock; //for foc reward
    address public devAddr;
    
    uint[] public depositTier; //requirements for deposit lock
    uint[] public rewardRatioByTier; //need to divide by 10000

    event Deposit(address who, uint pid, uint amount);
    event Withdraw(address who, uint pid, uint amount);
    event Rewards(address who, uint pid, uint rewards);
    event DepositTier(uint[] value);
    event RewardRatioByTier(uint[] value);

    constructor() {}

    function initialize(FocToken focToken_, address devAddr_,
        uint rewardPerBlock_, uint startBlock_) external virtual initializer {
        __FocFarming_init(focToken_, devAddr_, rewardPerBlock_, startBlock_);
    }

    function __FocFarming_init(FocToken focToken_, address devAddr_,
        uint rewardPerBlock_, uint startBlock_) internal initializer {
        __Ownable_init();
        __Pausable_init_unchained();
        require(address(focToken_) != address(0),"focToken_ address is null");
        focToken = focToken_;
        devAddr = devAddr_;
        rewardPerBlock = rewardPerBlock_;
        startBlock = startBlock_;
        totalLPAllocPoint = 0;
        depositTier = [0, 7 days, 14 days, 21 days, 28 days];
        rewardRatioByTier = [0, 1500, 4000, 6500, 10000];
    }

    function addLPPool(IERC20Upgradeable lpToken_, uint allocPoint_, uint lastRewardBlock_) onlyOwner external {
        require(address(lpToken_) != address(0),"lpToken_ address is null");
        lpPoolInfo.push(LPPoolInfo({
            lpToken: lpToken_,
            allocPoint: allocPoint_,
            lastRewardBlock: lastRewardBlock_,
            accRewardPerShare: 0
        }));
        totalLPAllocPoint += allocPoint_;
    }

    function resetLPPool(uint pid_, IERC20Upgradeable lpToken_, uint allocPoint_, uint lastRewardBlock_, uint accRewardPerShare_) onlyOwner external {
        totalLPAllocPoint = totalLPAllocPoint + allocPoint_ - lpPoolInfo[pid_].allocPoint;
        lpPoolInfo[pid_].lpToken = lpToken_;
        lpPoolInfo[pid_].allocPoint = allocPoint_;
        lpPoolInfo[pid_].lastRewardBlock = lastRewardBlock_;
        lpPoolInfo[pid_].accRewardPerShare = accRewardPerShare_;
    }

    function depositLP(uint _pid, uint _amount) external virtual onlyEOA whenNotPaused {
        require(_amount>0, "deposit amount is null");
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        UserLPInfo storage user = userLPInfo[_pid][_msgSender()];
        updateLPPool(_pid);
        //send pending reward first
        uint pending = pendingLPRewardByTier(_pid,_msgSender());
        if(pending > 0){
            focToken.mint(_msgSender(), pending);
            focToken.mint(devAddr, pending/20);
            emit Rewards(_msgSender(), _pid, pending);
        }

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
    
    // View function to see pending foc rewards rewards on frontend.
    function pendingLPReward(uint _pid, address _user) public view returns (uint pending_) {
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        UserLPInfo storage user = userLPInfo[_pid][_user];
        uint accRewardPerShare = lpPool.accRewardPerShare;
        uint lpSupply = lpPool.lpToken.balanceOf(address(this));
        uint pending;
        if (block.number > lpPool.lastRewardBlock && lpSupply != 0) {
            uint multiplier = block.number - lpPool.lastRewardBlock;
            uint focReward = multiplier * rewardPerBlock * lpPool.allocPoint / totalLPAllocPoint;
            accRewardPerShare = accRewardPerShare + (focReward * 1e12 / lpSupply);
        }
        pending = user.amount * accRewardPerShare / 1e12 - user.rewardDebt;
        return pending;
    }


    //front end function to return the "current" expected rewards
    function pendingLPRewardByTier(uint _pid, address _user) public view returns (uint pending_) {
        uint pending = pendingLPReward(_pid,_user);
        if(pending > 0){
            for(uint i = depositTier.length - 1; i >= 0 ; i--) {
                if(block.timestamp>= userLPInfo[_pid][_user].averageDepositedTime + depositTier[i]){
                    pending = pending * rewardRatioByTier[i] / 10000;
                    break;
                } 
            }
        }
        return pending;
    }

    //front end function to return the "current" tier for the user
    function currentUserTier(uint _pid, address _user) public view returns (uint x) {
        uint pending = pendingLPReward(_pid,_user);
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
    //update pool info
    function updateLPPool(uint _pid) public whenNotPaused {
        require(totalLPAllocPoint > 0, "totalLPAllocPoint is zero");
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        if (block.number <= lpPool.lastRewardBlock) { return;}
        uint lpSupply = lpPool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            lpPool.lastRewardBlock = block.number;
            return;
        }
        uint multiplier = block.number - lpPool.lastRewardBlock;
        uint focReward = multiplier * rewardPerBlock * lpPool.allocPoint / totalLPAllocPoint;
        lpPool.accRewardPerShare += focReward * 1e12 / lpSupply;
        lpPool.lastRewardBlock = block.number;
    }


    function withdrawLP(uint _pid, uint _amount) external virtual onlyEOA whenNotPaused {
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        UserLPInfo storage user = userLPInfo[_pid][_msgSender()];
        require(user.amount >= _amount, "withdraw amount overflow");
        updateLPPool(_pid);
        uint pending = pendingLPRewardByTier(_pid,_msgSender());

        if(pending > 0){
            focToken.mint(_msgSender(), pending);
            focToken.mint(devAddr, pending/20);
            emit Rewards(_msgSender(), _pid, pending);
        }

        if(_amount > 0) {
            lpPool.lpToken.safeTransfer(address(_msgSender()), _amount);
            if(_amount < user.amount) {
                //if not all withdrawn, update averageDepositedTime
                user.averageDepositedTime = block.timestamp;
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
        user.amount = 0;
        user.rewardDebt = 0;
        emit Withdraw(_msgSender(), _pid, user.amount);
    }
    
    function setRewardPerBlock(uint _rewardPerBlock) onlyOwner external {
        require(_rewardPerBlock != 0, "The RewardPerBlock is null");
        rewardPerBlock = _rewardPerBlock;
    }

    function setFocAddress(FocToken token_) onlyOwner external {
        require(address(token_) != address(0), "The address of token is null");
        focToken = token_;
    }

    function setDevAddress(address dev_) onlyOwner external {
        require(dev_ != address(0), "The address is null");
        devAddr = dev_;
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

    /*
     * @dev Pull out all balance of token or BNB in this contract. When tokenAddress_ is 0x0, will transfer all BNB to the admin owner.
     */
    function pullFunds(address tokenAddress_) onlyOwner external {
        LPPoolInfo storage lp1 = lpPoolInfo[0];
        LPPoolInfo storage lp2 = lpPoolInfo[1];
        LPPoolInfo storage lp3 = lpPoolInfo[2];
        require(tokenAddress_ != address(lp1.lpToken));
        require(tokenAddress_ != address(lp2.lpToken));
        require(tokenAddress_ != address(lp3.lpToken));
        if (tokenAddress_ == address(0)) {
            payable(_msgSender()).transfer(address(this).balance);
        } else {
            IERC20Upgradeable token = IERC20Upgradeable(tokenAddress_);
            token.transfer(_msgSender(), token.balanceOf(address(this)));
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

}