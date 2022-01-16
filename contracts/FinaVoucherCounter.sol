// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IFinaVoucher {
    function mint(address to, uint256 amount) external;
}

contract FinaVoucherCounter is Initializable, Ownable, Pausable {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private redeemTokenList;

    IFinaVoucher public voucherToken;

    uint public redeemAmount;

    event Redeemed(address who_, address redeemToken_, uint tokenId_);

    constructor() {}

    function initialize(IFinaVoucher voucherToken_, ERC721Burnable[] memory redeemTokens_, uint redeemAmount_)
    public initializer onlyOwner {
        require(redeemTokens_.length != 0, "FinaVoucherCounter: No redeem token was provided.");
        setVoucherToken(voucherToken_);
        setRedeemTokens(redeemTokens_);
        setRedeemAmount(redeemAmount_);
    }

    function redeem(address redeemToken_, uint tokenId_) whenNotPaused external {
        require(redeemToken_ != address(0), "FinaVoucherCounter: address cannot be null");
        require(redeemTokenList.contains(redeemToken_), "FinaVoucherCounter: invalid redeem token");
        require(ERC721Burnable(redeemToken_).ownerOf(tokenId_) == _msgSender(), "FinaVoucherCounter: not the token owner");

        ERC721Burnable(redeemToken_).burn(tokenId_);

        voucherToken.mint(_msgSender(), redeemAmount);

        emit Redeemed(_msgSender(), redeemToken_, tokenId_);
    }

    function setRedeemAmount(uint redeemAmount_) onlyOwner whenPaused public {
        require(redeemAmount_ > 0, "redeem amount should not be 0");
        redeemAmount = redeemAmount_;
    }

    function setRedeemTokens(ERC721Burnable[] memory redeemTokens_) onlyOwner whenPaused public {
        require(redeemTokens_.length != 0);
        uint length = redeemTokenList.length();
        for (uint i = 0; i < length; i++) {
            redeemTokenList.remove(redeemTokenList.at(0));
        }
        for (uint i = 0; i < redeemTokens_.length; i++) {
            redeemTokenList.add(address(redeemTokens_[i]));
        }
    }

    function setVoucherToken(IFinaVoucher voucherToken_) onlyOwner whenPaused public {
        require(voucherToken_ != IFinaVoucher(address(0)), "The address FinaVoucher token is null");
        voucherToken = voucherToken_;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /*
     * @dev Pull out all balance of token or BNB in this contract. When tokenAddress_ is 0x0, will transfer all BNB to the admin owner.
     */
    function pullFunds(address tokenAddress_) external onlyOwner() {
        if (tokenAddress_ == address(0)) {
            payable(_msgSender()).transfer(address(this).balance);
        } else {
            IERC20 token = IERC20(tokenAddress_);
            token.transfer(_msgSender(), token.balanceOf(address(this)));
        }
    }
}
