// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract FinaMaster is Ownable, Initializable {
    using Address for address;
    using SafeERC20 for IERC20;

    IERC20 public finaToken;

    event Deposited(address who, uint amount);
    event Withdraw(address who, uint amount);
    modifier onlyEOA() {
        require(msg.sender == tx.origin, "ForceNFTMarket: not eoa");
        _;
    }
    constructor() {}

    function deposit(uint amount_) external onlyEOA {
        require(amount_ != 0);
        finaToken.safeTransferFrom(_msgSender(), address(this), amount_);
        emit Deposited(_msgSender(),amount_);
    }

    function initialize(IERC20 token_) onlyOwner external initializer {
        require(address(token_) != address(0));
        finaToken = token_;
    }

    function setFinaAddress(IERC20 token_) onlyOwner external {
        require(token_ != IERC20(address(0)), "The address of token is null");
        finaToken = token_;
    }

    function multiSend(address[] memory recipients_, uint[] memory amount_) external onlyOwner {
        require(recipients_.length == amount_.length, "Value lengths do not match.");
        require(recipients_.length > 0, "The length is 0");
        for(uint i = 0; i < recipients_.length; i++){
            require(recipients_[i] != address(0));
            finaToken.safeTransfer(recipients_[i], amount_[i]);
            emit Withdraw(recipients_[i], amount_[i]);
        }
    }

    /*
     * @dev Pull out all balance of token or BNB in this contract. When tokenAddress_ is 0x0, will transfer all BNB to the admin owner.
     */
    function pullFunds(address tokenAddress_) onlyOwner external {
        if (tokenAddress_ == address(0)) {
            payable(_msgSender()).transfer(address(this).balance);
        } else {
            IERC20 token = IERC20(tokenAddress_);
            token.transfer(_msgSender(), token.balanceOf(address(this)));
        }
    }

}
