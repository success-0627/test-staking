pragma solidity ^0.8.5;

//import ERC20Upgradeable, etc... here
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";


//make standard ERC20 tokens below and deploy this twice as staked token and reward token
contract StakeToken is OwnableUpgradeable, ERC20Upgradeable, ERC20BurnableUpgradeable {
  function initialize() public initializer {
    __ERC20_init("Stake Token", "STT");
    __ERC20Burnable_init();

    // 100000 need to be update
    _mint(msg.sender, 100000 * 10 ** decimals());
  }

  function mint(address user, uint256 amount)
    public onlyOwner returns (bool) {
    super._mint(user, amount);

    return true;
  }
}

contract RewardToken is OwnableUpgradeable, ERC20Upgradeable, ERC20BurnableUpgradeable {
  function initialize() public initializer {
    __ERC20_init("Reward Token", "RWT");
    __ERC20Burnable_init();

    // 100000 need to be update
    _mint(msg.sender, 100000 * 10 ** decimals());
  }

  function mint(address user, uint256 amount)
    public onlyOwner returns (bool) {
    super._mint(user, amount);

    return true;
  }
}


//------------------------------==
//------------------------------==
contract SimpleStaking is Initializable, OwnableUpgradeable, PausableUpgradeable {
  //implement your code here to use SafeERC20Upgradeable and AddressUpgradeable
  using SafeERC20Upgradeable for StakeToken;
  using AddressUpgradeable for StakeToken;
  using SafeERC20Upgradeable for RewardToken;
  using AddressUpgradeable for RewardToken;

  address public rwTokenAddr;//reward token address
  uint256 public rewardInterval;
  
  struct Record {
    uint256 stakedAmount;
    uint256 stakedAt;
    uint256 unstakedAmount;
    uint256 unstakedAt;
    uint256 rewardAmount;
  }

  //implement your code here for "records", a mapping of token addresses and user addresses to an user Record struct
  struct TokenRecord {
    address tokenAddr;
    Record record;
  }
  mapping(address => TokenRecord[]) internal Records;

  //implement your code here for "rewardRates", a mapping of token address to reward rates. 
  // e.g. if APY is 20%, then rewardRate is 20.
  mapping(address => uint256) public rewardRates;


  event Stake(address indexed user, uint256 amount, uint256 stakedAt);
  event Unstake(address indexed user, uint256 amount, address indexed tokenAddr, uint256 reward, uint256 unstakedAt);
  event WithdrawUnstaked(address indexed user, uint256 amount, uint256 withdrawAt);
  event WithdrawRewards(address indexed user, uint256 amount, uint256 withdrawAt);
  event SetRewardRate(address indexed tokenAddr, uint256 newRewardRate);
  
  function initialize(address _rwTokenAddr) external initializer {
    //implement your code here
    rwTokenAddr = _rwTokenAddr;

    // 1000 is test value
    rewardInterval = 1000;

    __Ownable_init();
  }

  // for users to stake tokens
  function stake(address tokenAddr, uint256 amount) external whenNotPaused {
    require(amount > 0, "Cannot stake nothing");

    // get timestamp
    uint256 timestamp = block.timestamp;
    Record memory newRecord = Record(amount, timestamp, 0, 0, 0);

    ERC20(tokenAddr).transferFrom(msg.sender, address(this), amount);

    TokenRecord[] memory tokenRecords = Records[msg.sender];
    // user staked tokens before
    if(tokenRecords.length > 0) {
      // check token is staked
      bool tokenExist = false;
      for(uint256 ii = 0; ii < tokenRecords.length; ii += 1) {
        if(tokenRecords[ii].tokenAddr == tokenAddr) {
          Record memory selRecord = tokenRecords[ii].record;
          uint256 rewardVal = calculateReward(tokenAddr, msg.sender, selRecord.stakedAmount);
          if(rewardVal > 0) {
            ERC20(rwTokenAddr).transfer(address(this), rewardVal);
          }
          
          Records[msg.sender][ii].record = Record(selRecord.stakedAmount + amount, timestamp, selRecord.unstakedAmount, selRecord.unstakedAt, selRecord.rewardAmount + rewardVal);

          tokenExist = true;
          break;
        }
      }

      // if not staked
      if(!tokenExist) {
        Records[msg.sender].push(TokenRecord(tokenAddr, newRecord));
      }
    } else {
      Records[msg.sender].push(TokenRecord(tokenAddr, newRecord));
    }
    
    emit Stake(tokenAddr, amount, timestamp);
  }

  // for users to unstake their staked tokens
  function unstake(address tokenAddr, uint256 amount)
  external whenNotPaused {
    require(amount > 0, "Cannot unstake nothing");

    uint256 timestamp = block.timestamp;
    TokenRecord[] memory tokenRecords = Records[msg.sender];

    Record memory selRecord;
    uint256 selInd = 0;
    uint256 stakedAmount = 0;
    if(tokenRecords.length > 0) {
      for(uint256 ii = 0; ii < tokenRecords.length; ii += 1) {
        if(tokenRecords[ii].tokenAddr == tokenAddr) {
          selInd = ii;
          selRecord = tokenRecords[ii].record;
          stakedAmount = selRecord.stakedAmount;
          
          break;
        }
      }
    }

    require(stakedAmount > 0, "You didnt stake this token");

    require(amount <= stakedAmount, "Can not unstake over staked amount");
    uint256 rewardVal = calculateReward(tokenAddr, msg.sender, selRecord.stakedAmount);
    if(rewardVal > 0) {
      ERC20(rwTokenAddr).transfer(address(this), rewardVal);
    }
    Records[msg.sender][selInd].record = Record(selRecord.stakedAmount - amount, timestamp, selRecord.unstakedAmount + amount, timestamp, selRecord.rewardAmount + rewardVal);

    emit Unstake(msg.sender, amount, tokenAddr, 0, timestamp);
  }

  //for users to withdraw their unstaked tokens from this contract to the caller's address
  function withdrawUnstaked(address tokenAddr, uint256 _amount) external whenNotPaused {
    require(_amount > 0, "Can not withdraw nothing");

    uint256 timestamp = block.timestamp;

    TokenRecord[] memory tokenRecords = Records[msg.sender];

    Record memory selRecord;
    uint256 unstakedAmount = 0;
    uint256 selInd = 0;
    if(tokenRecords.length > 0) {
      for(uint256 ii = 0; ii < tokenRecords.length; ii += 1) {
        if(tokenRecords[ii].tokenAddr == tokenAddr) {
          selInd = ii;
          selRecord = tokenRecords[ii].record;
          unstakedAmount = selRecord.unstakedAmount;

          break;
        }
      }
    }

    require(unstakedAmount > 0, "You dont have any unstaked to withdraw");

    require(_amount <= unstakedAmount, "Can not withdraw over unstaked amount");

    // transfer stake token
    ERC20(tokenAddr).approve(address(this), _amount);
    ERC20(tokenAddr).transferFrom(address(this), msg.sender, _amount);
    Records[msg.sender][selInd].record = Record(selRecord.stakedAmount, selRecord.stakedAt, unstakedAmount - _amount, timestamp, selRecord.rewardAmount);

    emit WithdrawUnstaked(msg.sender, _amount, timestamp);
  }

  //for users to withdraw reward tokens from this contract to the caller's address
  function withdrawReward(address tokenAddr, uint256 _amount) external whenNotPaused {
    require(_amount > 0, "Can not withdraw nothing");

    TokenRecord[] memory tokenRecords = Records[msg.sender];

    uint256 rewardAmount = 0;
    Record memory selRecord;
    uint256 selInd = 0;
    if(tokenRecords.length > 0) {
      for(uint256 ii = 0; ii < tokenRecords.length; ii += 1) {
        if(tokenRecords[ii].tokenAddr == tokenAddr) {
          selInd = ii;
          selRecord = tokenRecords[ii].record;
          rewardAmount = selRecord.rewardAmount;
          
          break;
        }
      }
    }

    require(rewardAmount > 0, "You dont have any reward to withdraw");
    require(_amount <= rewardAmount, "Can not withdraw over reward amount");
          
    ERC20(rwTokenAddr).approve(address(this), _amount);
    ERC20(rwTokenAddr).transferFrom(address(this), msg.sender, _amount);
    Records[msg.sender][selInd].record = Record(selRecord.stakedAmount, selRecord.stakedAt, selRecord.unstakedAmount, selRecord.unstakedAt, selRecord.rewardAmount - _amount);

    emit WithdrawRewards(msg.sender, _amount, block.timestamp);
  }

  //to calculate rewards based on the duration of staked tokens, staked token amount, reward rate of the staked token, reward interval
  function calculateReward(address tokenAddr, address user, uint256 _amount) public view returns (uint256) {
    uint256 rateVal = rewardRates[tokenAddr];

    require(rateVal > 0, "Reward rate not exist");

    TokenRecord[] memory tokenRecords = Records[user];

    require(tokenRecords.length > 0, "You didnt stake any tokens");

    uint256 stakedAt = 0;
    for(uint256 ii = 0; ii < tokenRecords.length; ii += 1) {
      if(tokenRecords[ii].tokenAddr == tokenAddr) {
        stakedAt = tokenRecords[ii].record.stakedAt;
        break;
      }
    }

    require(stakedAt > 0, "Not stake this token");
    
    return ((block.timestamp - stakedAt) * _amount * rateVal) / rewardInterval;
  }

  //only for this contract owner to set the reward rate of a staked token
  function setRewardRate(address tokenAddr, uint256 rewardRate) external onlyOwner {
  // function setRewardRate(address tokenAddr, uint256 rewardRate) external {
    require(rewardRate > 0, "Reward rate should be bigger than zero");

    rewardRates[tokenAddr] = rewardRate;

    emit SetRewardRate(tokenAddr, rewardRate);
  }

  //only for this contract owner to pause this contract
  function pause() external onlyOwner whenNotPaused {
    super._pause();
  }

  //only for this contract owner to unpause this contract
  function unpause() external onlyOwner whenPaused {
    super._unpause();
  }
}