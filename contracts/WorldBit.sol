pragma solidity ^0.5.0;

import "./ERC20Mintable.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract WorldBit is ERC20, ERC20Burnable, ERC20Mintable, Ownable {
    string private _name = "WorldBit";
    string private _symbol = "WBT";
    uint8 private _decimals = 18;

    //Total Supply is 210,000,000 WBT
    uint256 private _totalSupply = 210000000 ether;

    constructor () public {
        _mint(msg.sender, _totalSupply);
        emit Transfer(address(0x0), msg.sender, _totalSupply);
    }

    // WorldBit Event and Emmit interface
    event WorldBitEvent(address object, bytes2 operand, bytes2 command, uint256 val1, uint256 val2, string location, string str1, string str2, string comment);

    function WorldBitRecord(address object, bytes2 operand, bytes2 command, uint256 val1, uint256 val2, string memory location, string memory str1, string memory str2, string memory comment) public {
        emit WorldBitEvent(object, operand, command, val1, val2, location, str1, str2, comment);
    }

    /**
    * @return the name of the token.
    */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
    * @return the symbol of the token.
    */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
    * @return the number of decimals of the token.
    */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    enum TxStatus { escrow, cancel, deliver, confirm, claim }

    struct Transaction {
        address user;
        address merchant;
        address asset;
        uint value;
        TxStatus status;
        bool completed;
    }

    mapping (uint => Transaction) public transactions;

    mapping (uint => mapping(address => uint)) public claims;

    uint public transactionCount;

    /**
    * Event for Escrow logging
    * @param transactionId Transaction ID
    * @param user user address
    * @param merchant merchant address
    * @param asset asset address
    * @param value escrowed value of WBT Token
    */
    event Escrow(uint transactionId, address indexed user, address indexed merchant, address indexed asset, uint value);

    /**
    * Event for Cancel logging
    * @param transactionId Transaction ID
    * @param from who canceled escrow
    */
    event Cancel(uint indexed transactionId, address indexed from);

    /**
    * Event for Deliver logging
    * @param transactionId Transaction ID
    */
    event Deliver(uint indexed transactionId);

    /**
    * Event for Confirm logging
    * @param transactionId Transaction ID
    */
    event Confirm(uint indexed transactionId);

    /**
    * Event for Claim logging
    * @param transactionId Transaction ID
    * @param from who claim
    */
    event Claim(uint indexed transactionId, address indexed from);

    /**
    * Event for Claim Handle logging
    * @param transactionId Transaction ID
    * @param beneficiary who got the WBT tokens
    * @param value claimed value
    */
    event HandleClaim(uint indexed transactionId, address indexed beneficiary, uint indexed value);

    /**
    * Event for Complete logging
    * @param transactionId Transaction ID
    */
    event Complete(uint transactionId);

    // -----------------------------------------
    // Escrow external interface
    // -----------------------------------------

    /**
    * @dev escrow tokens to address(this) contract and create pending transaction, called by user.
    * @param _merchant merchant address
    * @param _asset asset address
    * @param _value amount of tokens to escrow
    * @return Transaction ID
    */
    function escrow(address _merchant, address _asset, uint _value) external returns (uint transactionId) {
        // escrow funds from user wallet
        _transfer(msg.sender, address(address(this)), _value);
        transactionId = _addTransaction(msg.sender, _merchant, _asset, _value);
        emit Escrow(transactionId, msg.sender, _merchant, _asset, _value);
    }

    /**
    * @dev cancel transaction by user. User can cancel transaction if transaction is escrow state.
    * @param _transactionId Transaction ID
    * @return success
    */
    function cancelByUser(uint _transactionId) external onlyUser(_transactionId) notCompleted(_transactionId) returns (bool success) {
        require(transactions[_transactionId].status == TxStatus.escrow, "Only Transaction that is in escrow status can be canceled.");

        // transfer tokens back to user wallet
        _transfer(address(this), transactions[_transactionId].user, transactions[_transactionId].value);
        transactions[_transactionId].status = TxStatus.cancel;
        transactions[_transactionId].completed = true;

        emit Cancel(_transactionId, msg.sender);
        emit Complete(_transactionId);

        return true;
    }

    /**
    * @dev cancel transaction by merchant. Merchant can cancel transaction anytime.
    * @param _transactionId Transaction ID
    * @return success
    */
    function cancelByMerchant(uint _transactionId) external onlyMerchant(_transactionId) notCompleted(_transactionId) returns (bool success) {
        require(transactions[_transactionId].status == TxStatus.escrow || transactions[_transactionId].status == TxStatus.deliver, "Only transaction that is in escrow or deliver status can be canceled");

        // transfer WBT back to user wallet
        _transfer(address(this), transactions[_transactionId].user, transactions[_transactionId].value);
        transactions[_transactionId].status = TxStatus.cancel;
        transactions[_transactionId].completed = true;

        emit Cancel(_transactionId, msg.sender);
        emit Complete(_transactionId);

        return true;
    }

    /**
    * @dev mark transaction as deliver after merchant deliver asset.
    * @param _transactionId Transaction ID
    * @return success
    */
    function deliver(uint _transactionId) external onlyMerchant(_transactionId) notCompleted(_transactionId) returns (bool success) {
        require(transactions[_transactionId].status == TxStatus.escrow,  "Transaction status should be escrow");
        transactions[_transactionId].status = TxStatus.deliver;

        emit Deliver(_transactionId);

        return true;
    }

    /**
    * @dev confirm transaction. escrowed tokens will be transferred to merchant.
    * @param _transactionId Transaction ID
    * @return success
    */
    function confirm(uint _transactionId) external onlyUser(_transactionId) notCompleted(_transactionId) returns (bool success) {
        require(transactions[_transactionId].status == TxStatus.deliver, "Transaction status should be deliver");

        _transfer(address(this), transactions[_transactionId].merchant, transactions[_transactionId].value);

        transactions[_transactionId].status = TxStatus.confirm;
        transactions[_transactionId].completed = true;

        emit Confirm(_transactionId);
        emit Complete(_transactionId);

        return true;
    }

    /**
    * @dev User/Merchant mark transaction as claim when
    * User is not satisfied with deliverred item
    * User do not confirm after item is deliverred.
    * @param _transactionId Transaction ID
    * @return success
    */
    function claim(uint _transactionId) external onlyParties(_transactionId) notCompleted(_transactionId) returns (bool success) {
        require(claims[_transactionId][msg.sender] == 0, "Wrong Address");
        require(transactions[_transactionId].status == TxStatus.deliver || transactions[_transactionId].status == TxStatus.claim, "Transaction status should be deliver or claim");

        claims[_transactionId][msg.sender] = now;
        transactions[_transactionId].status = TxStatus.claim;

        emit Claim(_transactionId, msg.sender);

        return true;
    }

    /**
    * @dev Returns list of transaction IDs in defined range.
    * @param _from Index start position of transaction array.
    * @param _to Index end position of transaction array.
    * @param _status status of transactions.
    * @param _completed include completed transactions.
    */
    function getTransactionIds(uint _from, uint _to, TxStatus _status, bool _completed) external view returns (uint[] memory _transactionIds)
    {
        uint[] memory transactionIdsTemp = new uint[](transactionCount);
        uint count = 0;
        uint i;
        for (i = 0; i < transactionCount; i++)
        if (transactions[i].status == _status && transactions[i].completed == _completed)
        {
            transactionIdsTemp[count] = i;
            count += 1;
        }
        _transactionIds = new uint[](_to - _from);
        for (i = _from; i < _to; i++)
        _transactionIds[i - _from] = transactionIdsTemp[i];
    }

    /**
    * @dev Returns Transaction status
    * @param _transactionId Transaction ID
    */
    function getTransactionStatusById(uint _transactionId) external view returns (TxStatus status)
    {
        return transactions[_transactionId].status;
    }

    // -----------------------------------------
    // Interface for owner
    // -----------------------------------------

    /**
    * @dev mark transaction as deliver after merchant deliver asset.
    * @param _transactionId Transaction ID
    * @return success
    */
    function handleClaim(uint _transactionId, address _beneficiary) external notCompleted(_transactionId) onlyOwner returns (bool success) {
        require(_beneficiary == transactions[_transactionId].user || _beneficiary == transactions[_transactionId].merchant);

        _transfer(address(this), _beneficiary, transactions[_transactionId].value);
        transactions[_transactionId].completed = true;

        emit HandleClaim(_transactionId, _beneficiary, transactions[_transactionId].value);
        emit Complete(_transactionId);

        return true;
    }

    // -----------------------------------------
    // modifiers
    // -----------------------------------------
    modifier onlyUser(uint transactionId) {
        require(transactions[transactionId].user == msg.sender);
        _;
    }

    modifier onlyMerchant(uint transactionId) {
        require(transactions[transactionId].merchant == msg.sender);
        _;
    }

    modifier onlyParties(uint transactionId) {
        require(transactions[transactionId].merchant == msg.sender || transactions[transactionId].user == msg.sender);
        _;
    }

    modifier notCompleted(uint transactionId) {
        require(transactions[transactionId].user != address(0));
        require(!transactions[transactionId].completed);
        _;
    }

    // -----------------------------------------
    // Internal interface
    // -----------------------------------------

    /**
    * @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    * @param _user User Address.
    * @param _merchant Merchant Address.
    * @param _asset Asset Address.
    * @param _value Token Value of the transaction.
    * @return Returns transaction ID.
    */
    function _addTransaction(address _user, address _merchant, address _asset, uint _value) internal returns (uint transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            user: _user,
            merchant: _merchant,
            asset: _asset,
            value: _value,
            status: TxStatus.escrow,
            completed: false
        });
        transactionCount += 1;
    }
}