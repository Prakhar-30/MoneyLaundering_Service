// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract MultiPartyWallet is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    uint256 public creationTime;
    uint256 public totalContributions;
    bool public walletClosed;
    uint256 public minimumContribution;
    uint256 public closureTime;
    uint256 public additionalFunds;

    struct Shareholder {
        uint256 contribution;
        uint256 share;
    }

    mapping(address => Shareholder) public shareholders;
    address[] public shareholderAddresses;
    mapping(address => uint256) private shareholderIndex;
    bool[] public shareholderActive;
    

    event ContributionReceived(address indexed contributor, uint256 amount);
    event WalletClosed();
    event FundsDistributed(uint256 amount);
    event ShareCalculated(address indexed shareholder, uint256 share);
    event MinimumContributionUpdated(uint256 newMinimum);
    event SharesUpdated();
    event FallbackCalled(address sender, uint256 amount);
    event ClosureTimeUpdated(uint256 newClosureTime);
    event FundsReceived(address sender, uint256 amount);
    event FundsDistributedDirectly(uint256 amount);
    event ShareholderLeft(address indexed shareholder, uint256 amountWithdrawn, uint256 feesPaid);

    error WalletClosedError();
    error ContributionTooLowError();
    error NotClosedError();

    modifier onlyOpen() {
        if (walletClosed) revert WalletClosedError();
        _;
    }

    modifier onlyClosed() {
        if (!walletClosed) revert NotClosedError();
        _;
    }

    function initialize(uint256 _minimumContribution, uint256 _closureTime) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        creationTime = block.timestamp;
        walletClosed = false;
        minimumContribution = _minimumContribution;
        closureTime = _closureTime;
        shareholderActive = new bool[](0) ;
    }

    fallback() external payable {
        emit FallbackCalled(msg.sender, msg.value);
        if (walletClosed) {
            additionalFunds += msg.value;
            emit FundsReceived(msg.sender, msg.value);
        } else {
            contribute();
        }
    }

    function setMinimumContribution(uint256 _newMinimum) external onlyOwner onlyOpen {
        require(_newMinimum > 0, "Minimum contribution must be greater than 0");
        minimumContribution = _newMinimum;
        emit MinimumContributionUpdated(_newMinimum);
    }

    function setClosureTime(uint256 _newClosureTime) external onlyOwner onlyOpen {
        require(_newClosureTime > block.timestamp, "Closure time must be in the future");
        closureTime = _newClosureTime;
        emit ClosureTimeUpdated(_newClosureTime);
    }

    function contribute() public payable onlyOpen whenNotPaused {
        if (msg.value < minimumContribution) revert ContributionTooLowError();

        if (shareholders[msg.sender].contribution == 0) {
            shareholderIndex[msg.sender] = shareholderAddresses.length;
            shareholderAddresses.push(msg.sender);
            shareholderActive.push(true);
        }

        shareholders[msg.sender].contribution += msg.value;
        totalContributions += msg.value;

        emit ContributionReceived(msg.sender, msg.value);
    }

    function closeWallet() external onlyOpen {
        require(block.timestamp >= closureTime, "Cannot close wallet yet");
        walletClosed = true;
        updateShares();
        emit WalletClosed();
    }

    function updateShares() internal onlyClosed {
        for (uint256 i = 0; i < shareholderAddresses.length; i++) {
            if (shareholderActive[i]) {
                address shareholderAddress = shareholderAddresses[i];
                shareholders[shareholderAddress].share = (shareholders[shareholderAddress].contribution * 1e18) / totalContributions;
                emit ShareCalculated(shareholderAddress, shareholders[shareholderAddress].share);
            }
        }
        emit SharesUpdated();
    }

    function distributeAllFunds() internal onlyClosed nonReentrant {
        uint256 fundsToDistribute = additionalFunds;
        require(fundsToDistribute > 0, "No funds to distribute");

        for (uint256 i = 0; i < shareholderAddresses.length; i++) {
            if (shareholderActive[i]) {
                address shareholderAddress = shareholderAddresses[i];
                uint256 shareAmount = (fundsToDistribute * shareholders[shareholderAddress].share) / 1e18;

                if (shareAmount > 0) {
                    (bool success, ) = payable(shareholderAddress).call{value: shareAmount}("");
                    require(success, "Transfer failed");

                }
            }
        }

        additionalFunds = 0;
        emit FundsDistributedDirectly(fundsToDistribute);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable onlyClosed {
        additionalFunds += msg.value;

        emit FundsReceived(msg.sender, msg.value);

        distributeAllFunds();
    }
        function withdrawEther(uint256 _amount) external onlyOwner nonReentrant {
        require(_amount <= address(this).balance, "Insufficient balance");
        
        (bool success, ) = payable(owner()).call{value: _amount}("");
        require(success, "Transfer failed");
    }
}