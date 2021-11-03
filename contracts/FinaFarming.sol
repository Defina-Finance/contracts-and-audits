// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";


contract FinaFarming is Initializable, OwnableUpgradeable, PausableUpgradeable {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public finaToken;
    IERC20Upgradeable public secondRewardToken;

    modifier onlyEOA() {
        require(_msgSender() == tx.origin, "FinaFarming: not eoa");
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
    uint public rewardPerBlock; //for fina reward
    uint public secondRewardPerBlock; //for calculating second token as reward
    address public devAddr;

    event Deposit(address who, uint pid, uint amount);
    event Withdraw(address who, uint pid, uint amount);

    constructor() {}

    function initialize(IERC20Upgradeable finaToken_, IERC20Upgradeable secondToken_, address devAddr_,
        uint rewardPerBlock_, uint startBlock_) external virtual initializer {
        __FinaFarming_init(finaToken_, secondToken_, devAddr_, rewardPerBlock_, startBlock_);
    }

    function __FinaFarming_init(IERC20Upgradeable finaToken_, IERC20Upgradeable secondToken_, address devAddr_,
        uint rewardPerBlock_, uint startBlock_) internal initializer {
        __Ownable_init();
        __Pausable_init_unchained();
        require(address(finaToken_) != address(0),"finaToken_ address is null");
        require(address(secondToken_) != address(0),"secondToken_ address is null");
        require(address(devAddr_) != address(0),"devAddr_ address is null");
        require(rewardPerBlock_ > 0,"rewardPerBlock_ is zero");
        finaToken = finaToken_;
        secondRewardToken = secondToken_;
        devAddr = devAddr_;
        rewardPerBlock = rewardPerBlock_;
        startBlock = startBlock_;
        totalLPAllocPoint = 0;
    }

    function addLPPool(IERC20Upgradeable lpToken_, uint allocPoint_, uint lastRewardBlock_) onlyOwner external {
        require(address(lpToken_) != address(0),"lpToken_ address is null");
        require(allocPoint_ > 0, "allocPoint_ is zero");
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
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        UserLPInfo storage user = userLPInfo[_pid][_msgSender()];
        updateLPPool(_pid);
        if (user.amount > 0) {
            uint pending = user.amount * lpPool.accRewardPerShare / 1e12 - user.rewardDebt;
            //give second token as reward
            uint pendingExtra = pending * secondRewardPerBlock / rewardPerBlock;
            if(pending > 0) {
                finaToken.safeTransferFrom(address(this),_msgSender(), pending);
                secondRewardToken.safeTransferFrom(address(this), _msgSender(), pendingExtra);
            }
        }
        if (_amount > 0) {
            lpPool.lpToken.safeTransferFrom(address(_msgSender()), address(this), _amount);
            user.amount = user.amount + _amount;
        }
        user.rewardDebt = user.amount * lpPool.accRewardPerShare / 1e12;
        emit Deposit(_msgSender(), _pid, _amount);
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
        uint finaReward = multiplier * rewardPerBlock * lpPool.allocPoint / totalLPAllocPoint;
        lpPool.accRewardPerShare += finaReward * 1e12 / lpSupply;
        lpPool.lastRewardBlock = block.number;
    }

    // View function to see pending fina rewards and second token rewards on frontend.
    function pendingLPReward(uint _pid, address _user) public view returns (uint[] memory pending) {
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        UserLPInfo storage user = userLPInfo[_pid][_user];
        uint accRewardPerShare = lpPool.accRewardPerShare;
        uint lpSupply = lpPool.lpToken.balanceOf(address(this));
        if (block.number > lpPool.lastRewardBlock && lpSupply != 0) {
            uint multiplier = block.number - lpPool.lastRewardBlock;
            uint finaReward = multiplier * rewardPerBlock * lpPool.allocPoint / totalLPAllocPoint;
            accRewardPerShare = accRewardPerShare + (finaReward * 1e12 / lpSupply);
        }
        pending = new uint[](2);
        pending[0] = user.amount * accRewardPerShare / 1e12 - user.rewardDebt;
        pending[1] = pending[0] * secondRewardPerBlock / rewardPerBlock;
    }


    function withdrawLP(uint _pid, uint _amount) external virtual onlyEOA whenNotPaused {
        LPPoolInfo storage lpPool = lpPoolInfo[_pid];
        UserLPInfo storage user = userLPInfo[_pid][_msgSender()];
        require(user.amount >= _amount, "withdraw: not good");
        updateLPPool(_pid);
        uint pending = user.amount * lpPool.accRewardPerShare / 1e12 - user.rewardDebt;
        //give second token as reward
        uint pendingExtra = pending * secondRewardPerBlock / rewardPerBlock;
        if(pending > 0) {
            finaToken.safeTransferFrom(address(this),_msgSender(), pending);
            secondRewardToken.safeTransferFrom(address(this), _msgSender(), pendingExtra);
        }
        if(_amount > 0) {
            user.amount = user.amount - _amount;
            lpPool.lpToken.safeTransfer(address(_msgSender()), _amount);
        }
        user.rewardDebt = user.amount * lpPool.accRewardPerShare / 1e12;
        emit Withdraw(_msgSender(), _pid, _amount);
    }

    function setRewardPerBlock(uint _rewardPerBlock, uint _secondRewardPerBlock) onlyOwner external {
        require(_rewardPerBlock != 0, "The RewardPerBlock is null");
        require(_secondRewardPerBlock != 0, "The SecondRewardPerBlock is null");
        rewardPerBlock = _rewardPerBlock;
        secondRewardPerBlock = _secondRewardPerBlock;
    }

    function setFinaAddress(IERC20Upgradeable token_) onlyOwner external {
        require(address(token_) != address(0), "The address of token is null");
        finaToken = token_;
    }

    function setSecondTokenAddress(IERC20Upgradeable token_) onlyOwner external {
        require(address(token_) != address(0), "The address of token is null");
        secondRewardToken = token_;
    }

    function setDevAddress(address dev_) onlyOwner external {
        require(dev_ != address(0), "The address is null");
        devAddr = dev_;
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
