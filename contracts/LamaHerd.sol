// SPDX-License-Identifier: WTFPL License
pragma solidity >=0.6.0;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IMasterShepherd.sol";
import "../interfaces/ILamaHerd.sol";

contract LamaHerd is Ownable, ReentrancyGuard, ILamaHerd {
    using SafeMath for uint256;

    IBEP20 public lamaToken;
    address public devAddr;
    uint256 public lastWithdrawBalance;
    uint256 public totalRefFeesPaidSinceLastWithdraw;
    uint256 public unclaimedRefFees;

    mapping(address => address) public shepherds; // lama_address -> shepherd_address
    mapping(address => uint256) public referredCount; // shepherd_address -> num_of_lamas
    mapping(address => address[]) public lamas; // shepherd_address -> lama[]
    mapping(address => bool) public isAdmin;
    mapping(address => uint256) public shepherdsFees; // shepherd -> accrued fees

    event Referral(address indexed shepherd, address indexed lama);
    event EmergencyBEP20Drain(address token, address recipient, uint256 amount);

    constructor(
        address _lamaTokenAddr,
        address _devAddr,
        address _msAddr
    ) public {
        lamaToken = IBEP20(_lamaTokenAddr);
        devAddr = _devAddr;
        isAdmin[_msAddr] = true;
    }

    modifier onlyAdmin {
        require(isAdmin[msg.sender], "Not admin");
        _;
    }

    function setShepherd(address lama, address shepherd)
        external
        override
        onlyAdmin
    {
        // can't refer self
        if (lama == shepherd) return;
        // no mutual ref
        if (shepherds[shepherd] == lama) return;
        if (shepherds[lama] == address(0) && shepherd != address(0)) {
            shepherds[lama] = shepherd;
            referredCount[shepherd] += 1;
            address[] storage shepherdLamas = lamas[shepherd];
            shepherdLamas.push(lama);
            emit Referral(shepherd, lama);
        }
    }

    function setAdminStatus(address _admin, bool _status) external onlyOwner {
        isAdmin[_admin] = _status;
    }

    function withdrawDevReward() external nonReentrant {
        uint256 devAmt = getDevAvailableAmt();
        if (devAmt == 0) return;

        lamaToken.transfer(devAddr, devAmt);

        lastWithdrawBalance = lamaToken.balanceOf(address(this));
        totalRefFeesPaidSinceLastWithdraw = 0;
        unclaimedRefFees = 0;
    }

    function withdrawShepherdReward() external nonReentrant {
        uint256 amount = shepherdsFees[msg.sender];
        require(amount > 0, "No fees to withdraw");
        shepherdsFees[msg.sender] = 0;
        lamaToken.transfer(msg.sender, amount);
    }

    function payRefFees(address _lamaUser, uint256 _amtForShepherd)
        external
        override
        onlyAdmin
    {
        address shepherd = shepherds[_lamaUser];
        if (shepherd != address(0)) {
            totalRefFeesPaidSinceLastWithdraw = totalRefFeesPaidSinceLastWithdraw
                .add(_amtForShepherd);            
            shepherdsFees[shepherd] = shepherdsFees[shepherd].add(
                _amtForShepherd
            );
        } else {
            unclaimedRefFees = unclaimedRefFees.add(_amtForShepherd);
        }
    }

    function setInitialBalance(uint256 _amount) external onlyOwner {
        lamaToken.transferFrom(msg.sender, address(this), _amount);
        lastWithdrawBalance = _amount;
    }

    /**
     * @dev Owner can drain tokens that are sent here by mistake
     *
     * Requirements:
     *
     * - All tokens BUT LAMA can be drained
     */
    function drainStuckToken(address _token) external onlyOwner {
        require(_token != address(lamaToken), "LAMA can't be drained");
        IBEP20 token = IBEP20(_token);
        uint256 amount = token.balanceOf(address(this));
        token.transfer(msg.sender, amount);
        emit EmergencyBEP20Drain(address(token), msg.sender, amount);
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddr) public {
        require(msg.sender == devAddr, "dev: wut?");
        devAddr = _devAddr;
    }

    function setMasterShepherdDevAddr(address _masterShepherd, address _devAddr)
        external
        onlyOwner
    {
        IMasterShepherd(_masterShepherd).setDevAddress(_devAddr);
    }

    function getShepherd(address _lama)
        external
        view
        override
        returns (address)
    {
        return shepherds[_lama];
    }

    function getDevAvailableAmt() public view returns (uint256) {
        uint256 balance = lamaToken.balanceOf(address(this));
        if (balance == 0) return 0;
        uint256 grossAmtAvailable =
            balance.add(totalRefFeesPaidSinceLastWithdraw).sub(
                lastWithdrawBalance
            );
        uint256 devAmt = grossAmtAvailable.add(unclaimedRefFees);
        devAmt = devAmt.mul(800).div(1000);
        return devAmt;
    }
}
