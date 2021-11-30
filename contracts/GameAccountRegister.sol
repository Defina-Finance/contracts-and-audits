// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

contract GameAccountRegister is Initializable, AccessControlEnumerableUpgradeable {
    
    using AddressUpgradeable for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    mapping (address => bytes32) private accounts;
    mapping (address => bytes32) private delegatedAccounts;
    mapping (bytes32 => address) private emails;
    mapping (bytes32 => address) private delegatedEmails;
    EnumerableSetUpgradeable.AddressSet private accountsSet;

    event Binding(address indexed user, bytes32 account);
    event UnBinding(address indexed user);
    event Delegated(address indexed user, bytes32 delegatedAccount);
    event UnDelegated(address indexed user, bytes32 delegatedAccount);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor() {
    }

    function initialize() external initializer {
        __AccessControlEnumerable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    function bindAccount(string memory email_) external {
        require(bytes(email_).length > 0);
        bytes32 emailHash = _calcEmailHash(email_);
        bytes32 previousEmailHash = accounts[_msgSender()];
        if (previousEmailHash != 0) {
            delete emails[previousEmailHash];
        }
        require(emails[emailHash] == address(0), "The email has already been registered");
        require(delegatedEmails[emailHash] == address(0), "The email has already been registered as delegated account");
        accounts[_msgSender()] = emailHash;
        emails[emailHash] = _msgSender();

        accountsSet.add(_msgSender());

        emit Binding(_msgSender(), emailHash);
    }

    function delegateAccount(string memory email_) external {
        require(bytes(email_).length > 0);
        bytes32 emailHash = _calcEmailHash(email_);
        bytes32 previousEmailHash = delegatedAccounts[_msgSender()];
        if (previousEmailHash != 0) {
            delete delegatedEmails[previousEmailHash];
        }
        require(emails[emailHash] == address(0), "The email has already been registered as master account");
        require(delegatedEmails[emailHash] == address(0), "The email has already been registered as delegated account");
        delegatedAccounts[_msgSender()] = emailHash;
        delegatedEmails[emailHash] = _msgSender();
        emit Delegated(_msgSender(), emailHash);
    }

    function undelegateAccount(string memory email_) external {
        require(bytes(email_).length > 0);
        bytes32 emailHash = _calcEmailHash(email_);
        require(emailHash == delegatedAccounts[_msgSender()],"The email was not registered as the delegated account");
        require(delegatedEmails[emailHash] != address(0), "The email was not registered as delegated account");
        delete delegatedAccounts[_msgSender()];
        delete delegatedEmails[emailHash];
        emit UnDelegated(_msgSender(), emailHash);
    }

    function _removeAccount(address account_)  internal {
        bytes32 emailHash = accounts[account_];
        if (emailHash != 0) {
            delete accounts[account_];
            delete emails[emailHash];
        }
        bytes32 delegatedEmailHash = delegatedAccounts[account_];
        if ( delegatedEmailHash != 0) {
            delete delegatedAccounts[account_];
            delete delegatedEmails[delegatedEmailHash];
        }

        accountsSet.remove(account_);

        emit UnBinding(account_);
    }

    function removeAccount(address account_) onlyRole(ADMIN_ROLE) external {
        _removeAccount(account_);
    }

    function removeAllAccounts() onlyRole(ADMIN_ROLE) external {
        uint length = accountsSet.length();
        for (uint i = 0; i < length; i++) {
            _removeAccount(accountsSet.at(0));
        }
    }

    function getDelegatedEmailHash(address account_) external view returns(bytes32) {
        require(account_ != address(0));
        return delegatedAccounts[account_];
    }

    function getEmailHash(address account_) external view returns(bytes32) {
        require(account_ != address(0));
        return accounts[account_];
    }

    function calcEmailHash(string memory email_) external pure returns(bytes32) {
        return _calcEmailHash(email_);
    }

    function _calcEmailHash(string memory email_) internal pure returns(bytes32) {
        require(bytes(email_).length > 0);
        return keccak256(abi.encode(lower(email_)));
    }

    /*
     * @dev Pull out all balance of token or BNB in this contract. When tokenAddress_ is 0x0, will transfer all BNB to the admin owner.
     */
    function pullFunds(address tokenAddress_) onlyRole(ADMIN_ROLE) external {
        if (tokenAddress_ == address(0)) {
            payable(_msgSender()).transfer(address(this).balance);
        } else {
            IERC20Upgradeable token = IERC20Upgradeable (tokenAddress_);
            token.transfer(_msgSender(), token.balanceOf(address(this)));
        }
    }

    function lower(string memory _base) internal pure returns (string memory) {
        bytes memory _baseBytes = bytes(_base);
        for (uint i = 0; i < _baseBytes.length; i++) {
            _baseBytes[i] = _lower(_baseBytes[i]);
        }
        return string(_baseBytes);
    }

    function _lower(bytes1 _b1) private pure returns (bytes1) {
        if (_b1 >= 0x41 && _b1 <= 0x5A) {
            return bytes1(uint8(_b1) + 32);
        }
        return _b1;
    }
}