// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract P2PLending is ReentrancyGuard {
    using Address for address payable;

    address private _owner;
    address public dao;

    // Constants for HBAR (8 decimals)
    uint8 public constant HBAR_DECIMALS = 8;
    uint public constant MIN_LOAN_AMOUNT = 100000; // 0.001 HBAR in tinybars
    uint public constant MAX_LOAN_AMOUNT = 10000000000000; // 100000 HBAR in tinybars
    uint public constant MIN_INTEREST_RATE = 2; // 2%
    uint public constant MAX_INTEREST_RATE = 20; // 20%
    uint public constant SERVICE_FEE_PERCENTAGE = 2; // 2%

    struct Loan {
        uint loan_id;
        uint amount; // In tinybars for HBAR, token units for ERC20
        uint interest; // Percentage (e.g., 5 for 5%)
        uint duration; // Timestamp when loan expires
        uint repaymentAmount; // Total repayment (principal + interest)
        uint fundingDeadline; // Timestamp for funding deadline
        uint collateralAmount; // Token amount (ERC20) or token ID (ERC721)
        address borrower;
        address payable lender;
        address collateral; // Collateral contract address
        bool isCollateralErc20; // True for ERC20, false for ERC721
        bool active;
        bool repaid;
    }

    mapping(uint => Loan) public loans;
    mapping(address => uint) public defaulters;
    mapping(address => bool) public outstanding;
    mapping(address => bool) public acceptedCollaterals;
    address[] public acceptedCollateralsList;
    uint public loanCount;
    uint public totalServiceCharges;

    event LoanCreated(
        uint loanId,
        uint amount,
        uint interest,
        uint duration,
        uint fundingDeadline,
        address borrower,
        address lender
    );
    event LoanFunded(uint loanId, address funder, uint amount);
    event LoanRepaid(uint loanId, uint amount);
    event ServiceFeeDeducted(uint loanId, uint amount);
    event ServiceChargesWithdrawn(address owner, uint amount);
    event CollateralClaimed(uint loanId, address lender);
    event CollateralAdded(address collateral);
    event CollateralWithdrawn(uint loanId, address borrower);
    event LoanCancelled(uint loanId, address borrower);

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    modifier onlyActiveLoan(uint _loanId) {
        require(loans[_loanId].active, "Loan is not active");
        _;
    }

    modifier isCollateral(address _addr) {
        require(acceptedCollaterals[_addr], "Collateral not acceptable");
        _;
    }

    modifier onlyDao(address _caller) {
        require(_caller == dao, "Unauthorized");
        _;
    }

    modifier onlyBorrower(uint _loanId) {
        require(msg.sender == loans[_loanId].borrower, "Only borrower");
        _;
    }

    constructor(address _initialOwner, address _hdf, address _usdt, address _dai) {
        require(_initialOwner != address(0), "Invalid owner address");
        _owner = _initialOwner;
        _addCollateral(_hdf);
        _addCollateral(_usdt);
        _addCollateral(_dai);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner zero address");
        _owner = newOwner;
    }

    function setDaoAddress(address _dao) external onlyOwner {
        require(_dao != address(0), "Invalid DAO address");
        dao = _dao;
    }

    function addCollateral(address _collateral) external onlyOwner {
        require(_collateral != address(0), "Invalid collateral address");
        _addCollateral(_collateral);
        emit CollateralAdded(_collateral);
    }

    function _addCollateral(address _collateral) internal {
        acceptedCollaterals[_collateral] = true;
        acceptedCollateralsList.push(_collateral);
    }

    function getAllLoans() external view returns (Loan[] memory) {
        Loan[] memory allLoans = new Loan[](loanCount);
        for (uint i = 0; i < loanCount; i++) {
            allLoans[i] = loans[i];
        }
        return allLoans;
    }

    function createLoan(
        uint _amount,
        uint _interest,
        uint _duration,
        uint _collateralAmount,
        address _collateral,
        bool _isERC20,
        uint _fundingDeadline
    ) external payable nonReentrant isCollateral(_collateral) {
        require(_amount >= MIN_LOAN_AMOUNT && _amount <= MAX_LOAN_AMOUNT, "Loan amount invalid");
        require(_interest >= MIN_INTEREST_RATE && _interest <= MAX_INTEREST_RATE, "Interest invalid");
        require(_duration > 0, "Duration invalid");
        require(_fundingDeadline > block.timestamp, "Funding deadline must be in future");
        require(!outstanding[msg.sender], "Settle outstanding loan");

        // Validate HBAR amount for non-ERC20 loans
        if (!_isERC20) {
            require(msg.value == _amount, "Incorrect HBAR amount sent");
        } else {
            require(msg.value == 0, "No HBAR should be sent for ERC20 loans");
        }

        uint loanId = loanCount++;
        Loan storage loan = loans[loanId];

        uint _repaymentAmount = _amount + (_amount * _interest) / 100;

        loan.loan_id = loanId;
        loan.amount = _amount;
        loan.interest = _interest;
        loan.duration = _duration + block.timestamp;
        loan.collateral = _collateral;
        loan.collateralAmount = _collateralAmount;
        loan.repaymentAmount = _repaymentAmount;
        loan.fundingDeadline = _fundingDeadline;
        loan.borrower = msg.sender;
        loan.isCollateralErc20 = _isERC20;
        loan.lender = payable(address(0));
        loan.active = true;
        loan.repaid = false;

        // Transfer collateral
        if (_isERC20) {
            require(
                IERC20(_collateral).transferFrom(msg.sender, address(this), _collateralAmount),
                "ERC20 transfer failed"
            );
        } else {
            IERC721(_collateral).transferFrom(msg.sender, address(this), _collateralAmount);
        }

        outstanding[msg.sender] = true;

        emit LoanCreated(loanId, _amount, _interest, _duration, _fundingDeadline, msg.sender, address(0));
    }

    function fundLoan(uint _loanId) external payable nonReentrant onlyActiveLoan(_loanId) {
        Loan storage loan = loans[_loanId];
        require(msg.sender != loan.borrower, "Borrower can't fund own loan");
        require(block.timestamp <= loan.fundingDeadline, "Deadline passed");
        require(loan.lender == address(0), "Loan already funded");

        loan.lender = payable(msg.sender);
        outstanding[loan.borrower] = true;

        // Send funds to borrower
        payable(loan.borrower).sendValue(msg.value);

        emit LoanFunded(_loanId, msg.sender, msg.value);
    }

    function repayLoan(uint _loanId) external payable nonReentrant onlyBorrower(_loanId) {
        Loan storage loan = loans[_loanId];
        require(!loan.repaid, "Already repaid");

        uint serviceFee = (loan.repaymentAmount * SERVICE_FEE_PERCENTAGE) / 100;
        uint amountAfterFee = loan.repaymentAmount - serviceFee;

        totalServiceCharges += serviceFee;

        // Transfer repayment to lender
        loan.lender.sendValue(amountAfterFee);

        // Return collateral to borrower
        if (loan.isCollateralErc20) {
            require(
                IERC20(loan.collateral).transfer(msg.sender, loan.collateralAmount),
                "Failed to transfer ERC20 collateral"
            );
        } else {
            IERC721(loan.collateral).transferFrom(address(this), msg.sender, loan.collateralAmount);
        }

        loan.repaid = true;
        loan.active = false;
        outstanding[loan.borrower] = false;

        emit LoanRepaid(_loanId, loan.repaymentAmount);
        emit ServiceFeeDeducted(_loanId, serviceFee);
    }

    function getLoanInfo(uint _loanId) external view returns (Loan memory) {
        return loans[_loanId];
    }

    function claimCollateral(uint _loanId) external nonReentrant onlyActiveLoan(_loanId) {
        Loan storage loan = loans[_loanId];
        require(block.timestamp > loan.fundingDeadline && !loan.repaid, "Loan active or repaid");
        require(msg.sender == loan.lender, "Only lender can claim collateral");
        require(loan.lender != address(0), "No lender assigned");

        if (loan.isCollateralErc20) {
            require(
                IERC20(loan.collateral).transfer(msg.sender, loan.collateralAmount),
                "Failed to transfer ERC20 collateral"
            );
        } else {
            IERC721(loan.collateral).transferFrom(address(this), msg.sender, loan.collateralAmount);
        }

        loan.active = false;
        defaulters[loan.borrower] += 1;
        outstanding[loan.borrower] = false;

        emit CollateralClaimed(_loanId, msg.sender);
    }

    function withdrawFunds(uint _loanId) external nonReentrant onlyBorrower(_loanId) {
        Loan storage loan = loans[_loanId];
        require(loan.collateralAmount != 0, "No collateral found");
        require(loan.lender == address(0), "Loan already funded");

        if (loan.isCollateralErc20) {
            require(
                IERC20(loan.collateral).transfer(msg.sender, loan.collateralAmount),
                "Failed to transfer ERC20 collateral"
            );
        } else {
            IERC721(loan.collateral).transferFrom(address(this), msg.sender, loan.collateralAmount);
        }

        loan.active = false;
        loan.collateralAmount = 0;
        loan.collateral = address(0);
        outstanding[loan.borrower] = false;

        emit CollateralWithdrawn(_loanId, msg.sender);
    }

    function withdrawServiceCharges() external onlyOwner nonReentrant {
        require(totalServiceCharges > 0, "No service charges to withdraw");
        uint amount = totalServiceCharges;
        totalServiceCharges = 0;
        payable(_owner).sendValue(amount);
        emit ServiceChargesWithdrawn(_owner, amount);
    }

    // New functions added from the newer contract
    function cancelLoan(uint _loanId) external nonReentrant onlyBorrower(_loanId) onlyActiveLoan(_loanId) {
        Loan storage loan = loans[_loanId];
        require(loan.lender == address(0), "Loan already funded");
        require(block.timestamp <= loan.fundingDeadline, "Funding deadline passed");

        // Return collateral to borrower
        if (loan.isCollateralErc20) {
            require(
                IERC20(loan.collateral).transfer(msg.sender, loan.collateralAmount),
                "Failed to transfer ERC20 collateral"
            );
        } else {
            IERC721(loan.collateral).transferFrom(address(this), msg.sender, loan.collateralAmount);
        }

        loan.active = false;
        loan.collateralAmount = 0;
        loan.collateral = address(0);
        outstanding[msg.sender] = false;

        emit LoanCancelled(_loanId, msg.sender);
    }

    function getLoanStatus(uint _loanId) external view returns (string memory) {
        Loan memory loan = loans[_loanId];
        if (!loan.active) {
            if (loan.repaid) {
                return "Repaid";
            } else if (loan.lender == address(0) && loan.collateralAmount == 0) {
                return "Cancelled or Withdrawn";
            } else {
                return "Inactive";
            }
        }
        if (loan.lender != address(0)) {
            if (block.timestamp > loan.duration && !loan.repaid) {
                return "Defaulted";
            }
            return "Funded";
        }
        if (block.timestamp > loan.fundingDeadline) {
            return "Expired";
        }
        return "Pending";
    }

    function getBorrowerLoans(address _borrower) external view returns (Loan[] memory) {
        require(_borrower != address(0), "Invalid borrower address");
        uint count = 0;
        for (uint i = 0; i < loanCount; i++) {
            if (loans[i].borrower == _borrower) {
                count++;
            }
        }

        Loan[] memory borrowerLoans = new Loan[](count);
        uint index = 0;
        for (uint i = 0; i < loanCount; i++) {
            if (loans[i].borrower == _borrower) {
                borrowerLoans[index] = loans[i];
                index++;
            }
        }
        return borrowerLoans;
    }

    receive() external payable {
        // Allow contract to receive HBAR, but no specific logic needed
    }

    fallback() external payable {
        // Fallback for unexpected calls
    }
}