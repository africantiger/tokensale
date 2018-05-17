pragma solidity ^0.4.23;

// ----------------------------------------------------------------------------
//
// FTM 'Fantom' token public sale contract
//
// For details, please visit: http://fantom.foundation
//
//
// written by Alex Kampa - ak@sikoba.com
//
// ----------------------------------------------------------------------------


// ----------------------------------------------------------------------------
//
// SafeMath
//
// ----------------------------------------------------------------------------

library SafeMath {

    function add(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }

    function sub(uint a, uint b) internal pure returns (uint c) {
        require(b <= a);
        c = a - b;
    }

    function mul(uint a, uint b) internal pure returns (uint c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }
    
}


// ----------------------------------------------------------------------------
//
// Utils
//
// ----------------------------------------------------------------------------

contract Utils {
    
    function atNow() public view returns (uint) {
        return block.timestamp;
    }
    
}


// ----------------------------------------------------------------------------
//
// Owned
//
// ----------------------------------------------------------------------------

contract Owned {

    address public owner;
    address public newOwner;

    mapping(address => bool) public isAdmin;

    event OwnershipTransferProposed(address indexed _from, address indexed _to);
    event OwnershipTransferred(address indexed _from, address indexed _to);
    event AdminChange(address indexed _admin, bool _status);

    modifier onlyOwner { require(msg.sender == owner); _; }
    modifier onlyAdmin { require(isAdmin[msg.sender]); _; }

    constructor() public {
        owner = msg.sender;
        isAdmin[owner] = true;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0x0));
        emit OwnershipTransferProposed(owner, _newOwner);
        newOwner = _newOwner;
    }

    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function addAdmin(address _a) public onlyOwner {
        require(isAdmin[_a] == false);
        isAdmin[_a] = true;
        emit AdminChange(_a, true);
    }

    function removeAdmin(address _a) public onlyOwner {
        require(isAdmin[_a] == true);
        isAdmin[_a] = false;
        emit AdminChange(_a, false);
    }

}


// ----------------------------------------------------------------------------
//
// Wallet
//
// ----------------------------------------------------------------------------

contract Wallet is Owned {

    address public wallet;

    event WalletUpdated(address newWallet);

    constructor() public {
        wallet = owner;
    }

    function setWallet(address _wallet) public onlyOwner {
        require(_wallet != address(0x0));
        wallet = _wallet;
        emit WalletUpdated(_wallet);
    }

}


// ----------------------------------------------------------------------------
//
// ERC20Interface
//
// ----------------------------------------------------------------------------

contract ERC20Interface {

    event Transfer(address indexed _from, address indexed _to, uint _value);
    event Approval(address indexed _owner, address indexed _spender, uint _value);

    function totalSupply() public view returns (uint);
    function balanceOf(address _owner) public view returns (uint balance);
    function transfer(address _to, uint _value) public returns (bool success);
    function transferFrom(address _from, address _to, uint _value) public returns (bool success);
    function approve(address _spender, uint _value) public returns (bool success);
    function allowance(address _owner, address _spender) public view returns (uint remaining);

}


// ----------------------------------------------------------------------------
//
// ERC Token Standard #20
//
// ----------------------------------------------------------------------------

contract ERC20Token is ERC20Interface, Owned {

    using SafeMath for uint;

    uint public tokensIssuedTotal = 0;
    mapping(address => uint) balances;
    mapping(address => mapping (address => uint)) allowed;

    function totalSupply() public view returns (uint) {
        return tokensIssuedTotal;
    }

    function balanceOf(address _owner) public view returns (uint balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint _amount) public returns (bool success) {
        require(balances[msg.sender] >= _amount);
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        balances[_to]                = balances[_to].add(_amount);
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function approve(address _spender, uint _amount) public returns (bool success) {
        // require(balances[msg.sender] >= _amount);
        allowed[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint _amount) public returns (bool success) {
        require(balances[_from] >= _amount);
        require(allowed[_from][msg.sender] >= _amount);
        balances[_from] = balances[_from].sub(_amount);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        emit Transfer(_from, _to, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint remaining) {
        return allowed[_owner][_spender];
    }

}


// ----------------------------------------------------------------------------
//
// LockSlots
//
// ----------------------------------------------------------------------------

contract LockSlots is ERC20Token, Utils {

    using SafeMath for uint;

    uint8 public constant LOCK_SLOTS = 5;
    mapping(address => uint[LOCK_SLOTS]) public lockTerm;
    mapping(address => uint[LOCK_SLOTS]) public lockAmnt;
    mapping(address => bool) public hasLockedTokens;

    event RegisteredLockedTokens(address indexed account, uint indexed idx, uint tokens, uint term);

    function registerLockedTokens(address _account, uint _tokens, uint _term) internal returns (uint idx) {
        require(_term > atNow(), "lock term must be in the future"); 

        // find a slot (clean up while doing this)
        // use either the existing slot with the exact same term,
        // of which there can be at most one, or the first empty slot
        idx = 9999;    
        uint[LOCK_SLOTS] storage term = lockTerm[_account];
        uint[LOCK_SLOTS] storage amnt = lockAmnt[_account];
        for (uint i = 0; i < LOCK_SLOTS; i++) {
            if (term[i] < atNow()) {
                term[i] = 0;
                amnt[i] = 0;
                if (idx == 9999) idx = i;
            }
            if (term[i] == _term) idx = i;
        }

        // fail if no slot was found
        require(idx != 9999, "registerLockedTokens: no available slot found");

        // register locked tokens
        if (term[idx] == 0) term[idx] = _term;
        amnt[idx] = amnt[idx].add(_tokens);
        hasLockedTokens[_account] = true;
        emit RegisteredLockedTokens(_account, idx, _tokens, _term);
    }

    function lockedTokens(address _account) public view returns (uint locked) {
        if (!hasLockedTokens[_account]) return;
        uint[LOCK_SLOTS] storage term = lockTerm[_account];
        uint[LOCK_SLOTS] storage amnt = lockAmnt[_account];
        for (uint i = 0; i < LOCK_SLOTS; i++) {
            if (term[i] >= atNow()) locked = locked.add(amnt[i]);
        }
    }

    function unlockedTokens (address _account) public view returns (uint unlocked) {
        unlocked = balances[_account].sub(lockedTokens(_account));
    }

    function isAvailableLockSlot(address _account, uint _term) public view returns (bool) {
        if (_term < atNow()) return true;
        uint[LOCK_SLOTS] storage term = lockTerm[_account];
        for (uint i = 0; i < LOCK_SLOTS; i++) {
            if (term[i] < atNow() || term[i] == _term) return true;
        }
        return false;
    }
    
    // maintenance function
    
    function cleanLockSlots(address _account) public {
        require(hasLockedTokens[_account]); 
        uint locked;
        uint[LOCK_SLOTS] storage term = lockTerm[_account];
        uint[LOCK_SLOTS] storage amnt = lockAmnt[_account];
        for (uint i = 0; i < LOCK_SLOTS; i++) {
            if (term[i] < atNow()) {
                term[i] = 0;
                amnt[i] = 0;
            } else {
                locked = locked.add(amnt[i]);
            }
        }
        if (locked == 0) hasLockedTokens[_account] = false;
    }
    
}

// ----------------------------------------------------------------------------
//
// FantomIcoDates
//
// ----------------------------------------------------------------------------

contract FantomIcoDates is Owned, Utils {    

    uint public datePresaleStart = 1527861600; // 01-JUN-2018 14:00 UTC
    uint public datePresaleEnd   = 1527861600 + 15 days;
    uint public dateMainStart    = 1527861600 + 30 days;
    uint public dateMainEnd      = 1527861600 + 45 days;

    uint public constant DATE_LIMIT = 1527861600 + 180 days;

    event IcoDateUpdated(uint8 id, uint unixts);

    constructor() public {
        require(atNow() < datePresaleStart);
        checkDateOrder();
    }

    // check dates

    function checkDateOrder() internal view {
        require(datePresaleStart < datePresaleEnd);
        require(datePresaleEnd < dateMainStart);
        require(dateMainStart < dateMainEnd);
        require(dateMainEnd < DATE_LIMIT);
    }

    // set ico dates

    function setDatePresaleStart(uint _unixts) public onlyOwner {
        require(atNow() < _unixts && atNow() < datePresaleStart);
        datePresaleStart = _unixts;
        checkDateOrder();
        emit IcoDateUpdated(1, _unixts);
    }

    function setDatePresaleEnd(uint _unixts) public onlyOwner {
        require(atNow() < _unixts && atNow() < datePresaleEnd);
        datePresaleEnd = _unixts;
        checkDateOrder();
        emit IcoDateUpdated(2, _unixts);
    }

    function setDateMainStart(uint _unixts) public onlyOwner {
        require(atNow() < _unixts && atNow() < dateMainStart);
        dateMainStart = _unixts;
        checkDateOrder();
        emit IcoDateUpdated(3, _unixts);
    }

    function setDateMainEnd(uint _unixts) public onlyOwner {
        require(atNow() < _unixts && atNow() < dateMainEnd);
        dateMainEnd = _unixts;
        checkDateOrder();
        emit IcoDateUpdated(4, _unixts);
    }

    // where are we?

    function isPresaleFirstDay() public view returns (bool) {
        if (atNow() > datePresaleStart && atNow() <= datePresaleStart + 1 days) return true;
        return false;
    }

    function isPresale() public view returns (bool) {
        if (atNow() > datePresaleStart && atNow() < datePresaleEnd) return true;
        return false;
    }

    function isMainFirstDay() public view returns (bool) {
        if (atNow() > dateMainStart && atNow() <= dateMainStart + 1 days) return true;
        return false;
    }

    function isMain() public view returns (bool) {
        if (atNow() > dateMainStart && atNow() < dateMainEnd) return true;
        return false;
    }

}


// ----------------------------------------------------------------------------
//
// Fantom public token sale
//
// ----------------------------------------------------------------------------

contract FantomToken is ERC20Token, Wallet, LockSlots, FantomIcoDates {

    // Utility variable

    uint constant E18 = 10**18;
    
    // Basic token data

    string public constant name = "Fantom Token";
    string public constant symbol = "FTM";
    uint public constant decimals = 18;

    // crowdsale parameters

    uint public tokensPerEth = 10000;
    
    uint public constant MINIMUM_CONTRIBUTION    = 0.5 ether;

    uint public constant TOKEN_TOTAL_SUPPLY = 1000000000 * E18;
    uint public constant TOKEN_MINTING_CAP  =  400000000 * E18;
    uint public constant TOKEN_PRESALE_CAP  =  300000000 * E18; // includes bonus
    uint public constant TOKEN_MAIN_CAP     =  600000000 * E18;

    uint public constant BONUS = 15;

    bool public tokensTradeable;

    // whitelisting

    mapping(address => bool) public whitelist;
    uint public numberWhitelisted;

    // tokens issued
    // mapping(address => uint) balances; // in ERC20Token
    // uint public tokensIssuedTotal; // in ERC20Token

    uint public tokensMinted;
    uint public tokensPresale; // includes bonus
    uint public tokensMain;

    mapping(address => uint) public balancesPresaleBeforeBonus;
    mapping(address => uint) public balancesMain;

    mapping(address => uint) public ethContributed;
    uint public totalEthContributed;

    // Events ---------------------------------------------

    event Whitelisted(address indexed account, uint countWhitelisted);
    event UpdatedTokensPerEth(uint tokensPerEth);
    event TokensMinted(address indexed account, uint tokens, uint term);
    event RegisterContribution(address indexed account, bool indexed presale, uint tokens, uint bonus, uint ethContributed, uint ethReturned);

    // Basic Functions ------------------------------------

    constructor() public {
        require(TOKEN_TOTAL_SUPPLY == TOKEN_MINTING_CAP + TOKEN_MAIN_CAP);
        require(TOKEN_PRESALE_CAP < TOKEN_MAIN_CAP);
    }

    function () public payable {
        buyTokens();
    }

    // Information Functions ------------------------------
    
    function availableToMint() public view returns (uint available) {
        available = TOKEN_MINTING_CAP.sub(tokensMinted);
    }

    function firstDayLimitPresale() public view returns (uint) {
        if (numberWhitelisted == 0) return 0;
        return TOKEN_PRESALE_CAP.mul(100) / numberWhitelisted.mul(100 + BONUS);
    }

    function firstDayLimitMain() public view returns (uint) {
        if (numberWhitelisted == 0) return 0;
        return TOKEN_MAIN_CAP.sub(tokensPresale) / numberWhitelisted;
    }

    function ethToTokens(uint _eth) public view returns (uint tokens) {
        tokens = _eth.mul(tokensPerEth);
    }

    function tokensToEth(uint _tokens) public view returns (uint eth) {
        eth = _tokens / tokensPerEth;
    }

    // Whitelisting ---------------------------------------

    function addToWhitelist(address _account) public onlyAdmin {
        pWhitelist(_account);
    }

    function addToWhitelistMultiple(address[] _addresses) public onlyAdmin {
        for (uint i = 0; i < _addresses.length; i++) { 
            pWhitelist(_addresses[i]);
        }
    }

    function pWhitelist(address _account) internal {
        require(!isPresaleFirstDay() && !isMainFirstDay());
        if (whitelist[_account]) return;
        whitelist[_account] = true;
        numberWhitelisted = numberWhitelisted.add(1);
        emit Whitelisted(_account, numberWhitelisted);
    }

    // Owner functions ------------------------------------

    function updateTokensPerEth(uint _tokens_per_eth) public onlyAdmin {
        require(!isPresale() && !isMain());
        tokensPerEth = _tokens_per_eth;
        emit UpdatedTokensPerEth(tokensPerEth);
    }

    function makeTradeable() public onlyOwner {
        require(atNow() > dateMainEnd);
        tokensTradeable = true;
    }

    // Minting of unrestricted tokens ---------------------

    function mintTokens(address _account, uint _tokens) public onlyOwner {
        pMintTokens(_account, _tokens);
    }

    function mintTokensMultiple(address[] _accounts, uint[] _tokens) public onlyOwner {
        require(_accounts.length == _tokens.length);
        for (uint i = 0; i < _accounts.length; i++) {
            pMintTokens(_accounts[i], _tokens[i]);
        }
    }

    function pMintTokens(address _account, uint _tokens) private {
        // checks
        require(_account != 0x0);
        require(_tokens > 0);
        require(_tokens <= availableToMint(), "not enough tokens available to mint");

        // update
        balances[_account] = balances[_account].add(_tokens);
        tokensMinted = tokensMinted.add(_tokens);
        tokensIssuedTotal = tokensIssuedTotal.add(_tokens);

        // log event
        emit Transfer(0x0, _account, _tokens);
        emit TokensMinted(_account, _tokens, 0);
    }

    // Minting of locked tokens -----------------------------

    function mintTokensLocked(address _account, uint _tokens, uint _term) public onlyOwner {
        pMintTokensLocked(_account, _tokens, _term);
    }

    function mintTokensLockedMultiple(address[] _accounts, uint[] _tokens, uint[] _terms) public onlyOwner {
        require(_accounts.length == _tokens.length);
        require(_accounts.length == _terms.length);
        for (uint i = 0; i < _accounts.length; i++) {
            pMintTokensLocked(_accounts[i], _tokens[i], _terms[i]);
        }
    }

    function pMintTokensLocked(address _account, uint _tokens, uint _term) private {
        require(_account != 0x0);
        require(_tokens > 0);
        require(_tokens <= availableToMint(), "not enough tokens available to mint");
        require(_term > atNow(), "lock term must be in the future");

        // register locked tokens (will throw if no slot is found)
        registerLockedTokens(_account, _tokens, _term);

        // update
        balances[_account] = balances[_account].add(_tokens);
        tokensMinted = tokensMinted.add(_tokens);
        tokensIssuedTotal = tokensIssuedTotal.add(_tokens);

        // log event
        emit Transfer(0x0, _account, _tokens);
        emit TokensMinted(_account, _tokens, _term);
    }

    // Process ICO contributions ----------------------------

    function buyTokens() private {

        require(isPresale() || isMain());
        require(msg.value >= MINIMUM_CONTRIBUTION);
        require(whitelist[msg.sender]);

        uint tokens_requested = ethToTokens(msg.value);
        uint tokens_available;

        uint tokens = tokens_requested; // = tokens_issued + tokens_bonus
        uint tokens_issued = tokens_requested;
        uint tokens_bonus;
        uint tokens_rejected;

        uint eth_contributed = msg.value;
        uint eth_returned;

        if (isPresaleFirstDay()) {
            tokens_available = firstDayLimitPresale().sub(balancesPresaleBeforeBonus[msg.sender]);
        } else if (isPresale()) {
            tokens_available = TOKEN_PRESALE_CAP.sub(tokensPresale).mul(100) / (100 + BONUS);
        } else if (isMainFirstDay()) {
            tokens_available = firstDayLimitMain().sub(balancesMain[msg.sender]);
        } else if (isMain()) {
            tokens_available = TOKEN_MAIN_CAP.sub(tokensPresale).sub(tokensMain);
        }

        require (tokens_available > 0);

        if (tokens_requested > tokens_available) {
            tokens = tokens_available;
            tokens_issued = tokens_available;
            tokens_rejected = tokens_requested.sub(tokens_available);
            eth_returned = tokensToEth(tokens_rejected);
            eth_contributed = msg.value.sub(eth_returned);
        }

        if (isPresale()) {
            tokens_bonus = tokens_issued.mul(BONUS) / 100;
            tokens = tokens.add(tokens_bonus);
            balancesPresaleBeforeBonus[msg.sender] = balancesPresaleBeforeBonus[msg.sender].add(tokens_issued);
            tokensPresale = tokensPresale.add(tokens);
        } else if (isMain()) {
            balancesMain[msg.sender] = balancesMain[msg.sender].add(tokens);
            tokensMain = tokensMain.add(tokens);
        }

        balances[msg.sender] = balances[msg.sender].add(tokens);
        tokensIssuedTotal = tokensIssuedTotal.add(tokens);
        ethContributed[msg.sender] = ethContributed[msg.sender].add(eth_contributed);
        totalEthContributed = totalEthContributed.add(eth_contributed);

        // ether transfers
        if (eth_returned > 0) msg.sender.transfer(eth_returned);
        wallet.transfer(eth_contributed);

        // log
        emit Transfer(0x0, msg.sender, tokens_issued.add(tokens_bonus));
        emit RegisterContribution(msg.sender, isPresale(), tokens, tokens_bonus, eth_contributed, eth_returned);
    }


    // ERC20 functions -------------------

    /* Transfer out any accidentally sent ERC20 tokens */

    function transferAnyERC20Token(address tokenAddress, uint amount) public onlyOwner returns (bool success) {
            return ERC20Interface(tokenAddress).transfer(owner, amount);
    }

    /* Override "transfer" */

    function transfer(address _to, uint _amount) public returns (bool success) {
        require(tokensTradeable);
        require(_amount <= unlockedTokens(msg.sender));
        return super.transfer(_to, _amount);
    }

    /* Override "transferFrom" */

    function transferFrom(address _from, address _to, uint _amount) public returns (bool success) {
        require(tokensTradeable);
        require(_amount <= unlockedTokens(_from)); 
        return super.transferFrom(_from, _to, _amount);
    }

    /* Multiple token transfers from one address to save gas */

    function transferMultiple(address[] _addresses, uint[] _amounts) external {
        require(tokensTradeable);
        require(_addresses.length <= 100);
        require(_addresses.length == _amounts.length);

        // check token amounts
        uint tokens_to_transfer = 0;
        for (uint i = 0; i < _addresses.length; i++) {
            tokens_to_transfer = tokens_to_transfer.add(_amounts[i]);
        }
        require(tokens_to_transfer <= unlockedTokens(msg.sender));

        // do the transfers
        for (i = 0; i < _addresses.length; i++) {
            super.transfer(_addresses[i], _amounts[i]);
        }
    }

}