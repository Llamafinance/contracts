// SPDX-License-Identifier: WTFPL License
pragma solidity 0.6.12;

import '../node_modules/@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '../node_modules/@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '../node_modules/@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '../node_modules/@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';

import "./LlamaToken.sol";

//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once LAMA is sufficiently
// distributed and the community can show to govern itself.
//
contract MasterShepherd is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of LAMAs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLamaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accLamaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. LAMAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that LAMAs distribution occurs.
        uint256 accLamaPerShare;   // Accumulated LAMAs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The LAMA TOKEN
    LlamaToken public lama;    
    // Dev address.
    address public devaddr;
    // LAMA tokens created per block.
    uint256 public lamaPerBlock;
    // Bonus muliplier for early lama makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // The maximum deposit fee allowed is 10%
    uint16 public MAX_DEPOSIT_FEE = 1000;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when LAMA mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        LlamaToken _lama,        
        address _devaddr,
        address _feeAddress,
        uint256 _lamaPerBlock       
    ) public {
        lama = _lama;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        lamaPerBlock = _lamaPerBlock;                
    }
    
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setStartBlock(uint256 _startBlock) public onlyOwner {
        require(startBlock == 0, "already started");
        startBlock = _startBlock;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX Adding the same LP token more than once is not allowed.
    function add(uint256 _allocPoint, IBEP20 _lpToken,  uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= MAX_DEPOSIT_FEE, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        checkPoolDuplicate(_lpToken);
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accLamaPerShare: 0,
            depositFeeBP: _depositFeeBP
        }));        
    }

    // Detects whether the given pool already exists
    function checkPoolDuplicate(IBEP20 _lpToken) public view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: existing pool");
        }
    }

    // Update the given pool's LAMA allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner validatePool(_pid) {
        require(_depositFeeBP <= MAX_DEPOSIT_FEE, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }       
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }
        
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }
        
    // View function to see pending LAMAs on frontend.
    function pendingLama(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLamaPerShare = pool.accLamaPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 lamaReward = multiplier.mul(lamaPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accLamaPerShare = accLamaPerShare.add(lamaReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accLamaPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 lamaReward = multiplier.mul(lamaPerBlock).mul(pool.allocPoint).div(totalAllocPoint);                
        lama.mint(devaddr, lamaReward.div(10));
        lama.mint(address(this), lamaReward);
        pool.accLamaPerShare = pool.accLamaPerShare.add(lamaReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for LAMA allocation.
    function deposit(uint256 _pid, uint256 _amount) public {        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accLamaPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeLamaTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accLamaPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterShepherd.
    function withdraw(uint256 _pid, uint256 _amount) public validatePool(_pid) {       
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accLamaPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeLamaTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLamaPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }
    
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe lama transfer function, just in case if rounding error causes pool to not have enough LAMAs.
    function safeLamaTransfer(address _to, uint256 _amount) internal {
        uint256 lamaBal = lama.balanceOf(address(this));
        if (_amount > lamaBal) {
            lama.transfer(_to, lamaBal);
        } else {
            lama.transfer(_to, _amount);
        }
    }
    modifier validatePool(uint256 _pid) {
        require(_pid < poolInfo.length, "validatePool: pool exists?");
        _;
    }

    function updateBonusMultiplier(uint256 _multiplierNumber) external onlyOwner {
        require( _multiplierNumber <= 3, "can't be more than 3" );
        BONUS_MULTIPLIER = _multiplierNumber;
    }
    
    function updateLamaPerBlock(uint256 _lamaPerBlock) external onlyOwner {        
        massUpdatePools();
        lamaPerBlock = _lamaPerBlock;
    }
                              
    // Update dev address by the previous dev.
    function setDevAddress(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    // Update fee address by the previous address
    function setFeeAddress(address _feeAddress) public{
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }
}