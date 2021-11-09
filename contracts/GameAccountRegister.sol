// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract GameAccountRegister is Initializable, AccessControlEnumerableUpgradeable {
    
    using AddressUpgradeable for address;
    mapping (address => bytes32) private accounts;
    mapping (address => bytes32) private delegatedAccounts;
    mapping (bytes32 => address) private emails;
    mapping (bytes32 => address) private delegatedEmails;

    event Binding(address user, bytes32 account);
    event UnBinding(address user);
    event Delegated(address user, bytes32 delegatedAccount);
    event UnDelegated(address user, bytes32 delegatedAccount);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor() {
    }

    function initialize() external initializer {
        __AccessControlEnumerable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    function bindAccount(string memory _email) external {
        require(bytes(_email).length > 0);
        bytes32 emailHash = _calcEmailHash(_email);
        bytes32 previousEmailHash = accounts[_msgSender()];
        if (previousEmailHash != 0) {
            delete emails[previousEmailHash];
        }
        require(emails[emailHash] == address(0), "The email has already been registered");
        require(delegatedEmails[emailHash] == address(0), "The email has already been registered as delegated account");
        accounts[_msgSender()] = emailHash;
        emails[emailHash] = _msgSender();
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
        require(delegatedEmails[emailHash] != address(0), "The email was not registered as delegated account");
        delete delegatedAccounts[_msgSender()];
        delete delegatedEmails[emailHash];
        emit UnDelegated(_msgSender(), emailHash);
    }

    function removeAccount(address account_) onlyRole(ADMIN_ROLE) external {
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
        emit UnBinding(account_);
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
        return keccak256(abi.encode(email_));
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

}