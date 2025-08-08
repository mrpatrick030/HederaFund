// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IERC721Minimal {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract P2PLending {
    address private _owner;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    constructor(
        address _initialOwner,
        address HDF,
        address usdt,
        address dai
    ) {
        _owner = _initialOwner;
        _addCollateral(HDF);
        _addCollateral(usdt);
        _addCollateral(dai);
    }

    // Ownership functions
    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner zero address");
        _owner = newOwner;
    }

    // Constants
    uint public constant MIN_LOAN_AMOUNT = 0.001 ether;
    uint public constant MAX_LOAN_AMOUNT = 100000 ether;
    uint public constant MIN_INTEREST_RATE = 2;
    uint public constant MAX_INTEREST_RATE = 20;
    uint public constant SERVICE_FEE_PERCENTAGE = 2;

    struct Loan {
        uint loan_id;
        uint amount;
        uint interest;
        uint duration;
        uint repaymentAmount;
        uint fundingDeadline;
        uint collateralAmount;
        address borrower;
        address payable lender;
        address collateral;
        bool isCollateralErc20;
        bool active;
        bool repaid;
    }

    mapping(uint => Loan) public loans;
    mapping(address => uint) public defaulters;
    mapping(address => bool) public outstanding;
    mapping(address => bool) public accepteddCollaterals;
    address[] public accepted_collaterals;
    uint public loanCount;
    address public dao;
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

    modifier onlyActiveLoan(uint _loanId) {
        require(loans[_loanId].active, "Loan is not active");
        _;
    }

    modifier isCollateral(address _addr) {
        require(accepteddCollaterals[_addr] == true, "Collateral not acceptable");
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

    function setadaoaddress(address _dao) public onlyOwner {
        dao = _dao;
    }

    function addCollateral(address _collateral) public onlyOwner {
        _addCollateral(_collateral);
        emit CollateralAdded(_collateral);
    }

    function _addCollateral(address _collateral) internal {
        accepteddCollaterals[_collateral] = true;
        accepted_collaterals.push(_collateral);
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
    ) external payable isCollateral(_collateral) {
        require(_amount >= MIN_LOAN_AMOUNT && _amount <= MAX_LOAN_AMOUNT, "Loan amount invalid");
        require(_interest >= MIN_INTEREST_RATE && _interest <= MAX_INTEREST_RATE, "Interest invalid");
        require(_duration > 0, "Duration invalid");
        require(!outstanding[msg.sender], "Settle outstanding loan");

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
        loan.fundingDeadline = _fundingDeadline + block.timestamp;
        loan.borrower = msg.sender;
        loan.isCollateralErc20 = _isERC20;
        loan.lender = payable(address(0));
        loan.active = true;
        loan.repaid = false;

        if (_isERC20) {
            require(
                IERC20Minimal(_collateral).transferFrom(msg.sender, address(this), _collateralAmount),
                "ERC20 transfer failed"
            );
        } else {
            IERC721Minimal(_collateral).transferFrom(msg.sender, address(this), _collateralAmount);
        }

        emit LoanCreated(loanId, _amount, _interest, _duration, _fundingDeadline, msg.sender, address(0));
    }

    function fundLoan(uint _loanId) external payable onlyActiveLoan(_loanId) {
        Loan storage loan = loans[_loanId];
        require(msg.sender != loan.borrower, "Borrower can't fund own loan");
        require(block.timestamp <= loan.fundingDeadline, "Deadline passed");
        require(msg.value == loan.amount, "Incorrect funding amount");

        loan.lender = payable(msg.sender);
        outstanding[loan.borrower] = true;

        // Send the funded amount to the borrower
        payable(loan.borrower).transfer(msg.value);

        emit LoanFunded(_loanId, msg.sender, msg.value);
    }

    function repayLoan(uint _loanId) external payable onlyActiveLoan(_loanId) onlyBorrower(_loanId) {
        Loan storage loan = loans[_loanId];
        require(!loan.repaid, "Already repaid");

        uint interestAmount = (loan.amount * loan.interest) / 100;
        uint repaymentAmount = loan.amount + interestAmount;
        require(msg.value >= repaymentAmount, "Insufficient repayment");

        uint serviceFee = (repaymentAmount * SERVICE_FEE_PERCENTAGE) / 100;
        uint amountAfterFee = repaymentAmount - serviceFee;

        loan.lender.transfer(amountAfterFee);
        // Since treasury removed, service fee remains in contract or you can implement withdrawal later

        if (loan.isCollateralErc20) {
            require(
                IERC20Minimal(loan.collateral).transfer(msg.sender, loan.collateralAmount),
                "Failed to transfer ERC20 collateral"
            );
        } else {
            IERC721Minimal(loan.collateral).transferFrom(address(this), msg.sender, loan.collateralAmount);
        }

        totalServiceCharges += serviceFee;

        emit LoanRepaid(_loanId, repaymentAmount);
        emit ServiceFeeDeducted(_loanId, serviceFee);

        loan.repaid = true;
        outstanding[loan.borrower] = false;
        loan.active = false;
    }

    function getLoanInfo(uint _loanId) external view returns (Loan memory) {
        return loans[_loanId];
    }

    function claimCollateral(uint _loanId) external onlyActiveLoan(_loanId) {
        Loan storage loan = loans[_loanId];
        require(block.timestamp > loan.fundingDeadline && !loan.repaid, "Loan active or repaid");
        require(msg.sender == loan.lender, "Only lender can claim collateral");

        if (loan.isCollateralErc20) {
            require(
                IERC20Minimal(loan.collateral).transfer(msg.sender, loan.collateralAmount),
                "Failed to transfer ERC20 collateral"
            );
        } else {
            IERC721Minimal(loan.collateral).transferFrom(address(this), msg.sender, loan.collateralAmount);
        }

        loan.active = false;
        defaulters[loan.borrower] += 1;
        outstanding[loan.borrower] = false;

        emit CollateralClaimed(_loanId, msg.sender);
    }

    function withdrawFunds(uint _loanId) external onlyBorrower(_loanId) {
        Loan storage loan = loans[_loanId];
        require(loan.collateralAmount != 0, "No collateral found");
        require(block.timestamp > loan.fundingDeadline, "Funding deadline not passed");

        if (loan.isCollateralErc20) {
            require(
                IERC20Minimal(loan.collateral).transfer(msg.sender, loan.collateralAmount),
                "Failed to transfer ERC20 collateral"
            );
        } else {
            IERC721Minimal(loan.collateral).transferFrom(address(this), msg.sender, loan.collateralAmount);
        }

        loan.active = false;
        loan.collateralAmount = 0;
        loan.collateral = address(0);
    }

    // Uncomment if you want to allow owner to withdraw accumulated service fees
    /*
    function withdrawServiceCharges() external onlyOwner {
        require(totalServiceCharges > 0, "No service charges to withdraw");
        payable(owner()).transfer(totalServiceCharges);
        emit ServiceChargesWithdrawn(owner(), totalServiceCharges);
        totalServiceCharges = 0;
    }
    */

    receive() external payable {}
    fallback() external payable {}
}
