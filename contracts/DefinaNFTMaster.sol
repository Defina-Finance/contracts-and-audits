// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";


contract DefinaNFTMaster is Ownable, ERC721Holder, Initializable, Pausable {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    event NFTWithdraw(address indexed _who, uint indexed _tokenId);
    event NFTStaked(address indexed _who, uint indexed tokenId);

    EnumerableMap.UintToAddressMap private stakeMap;
    IERC721Enumerable public nftToken;

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "DefinaNFTMaster: not eoa");
        _;
    }

    constructor() {}

    function initialize(IERC721Enumerable nft_) onlyOwner public initializer {
        nftToken = nft_;
    }

    function stake(uint tokenId_) public onlyEOA whenNotPaused {
        require(nftToken.ownerOf(tokenId_) == _msgSender(), "tokenId are not owned by the caller");
        nftToken.safeTransferFrom(_msgSender(), address(this), tokenId_);
        stakeMap.set(tokenId_, _msgSender());
        emit NFTStaked(_msgSender(), tokenId_);
    }

    function stakeMulti(uint[] memory tokenIds_) external onlyEOA whenNotPaused {
        require(tokenIds_.length != 0);
        for (uint i = 0; i < tokenIds_.length; i++) {
            stake(tokenIds_[i]);
        }
    }

    function withdraw(uint tokenId_) public onlyEOA whenNotPaused {
        require(nftToken.ownerOf(tokenId_) == address(this), "tokenId is not owned by the contract");
        require(stakeMap.contains(tokenId_), "tokenId was not staked");
        require(stakeMap.get(tokenId_) == _msgSender(), "the tokenId was not staked by the caller");
        stakeMap.remove(tokenId_);
        nftToken.safeTransferFrom(address(this), _msgSender(), tokenId_);
        emit NFTWithdraw(_msgSender(), tokenId_);
    }

    function withdrawMulti(uint[] memory tokenIds_) external onlyEOA whenNotPaused {
        require(tokenIds_.length != 0);
        for (uint i = 0; i < tokenIds_.length; i++) {
            withdraw(tokenIds_[i]);
        }
    }

    function getAddressStakedToken(uint tokenId_) view external returns(address) {
        require(stakeMap.contains(tokenId_), "tokenId was not staked");
        return stakeMap.get(tokenId_);
    }

    function isStaked(uint tokenId_) view external returns(bool) {
        return stakeMap.contains(tokenId_);
    }

    function getTokensStakedByAddress(address who) view external returns(uint[] memory tokenIds_) {
        require(who != address(0));
        uint length = stakeMap.length();
        uint[] memory tmp = new uint[](length);

        uint index = 0;
        for (uint i = 0; i < length; i++) {
            (uint _tokenId, address _staker) = stakeMap.at(i);
            if (who == _staker) {
                tmp[index] = _tokenId;
                index++;
            }
        }
        tokenIds_ = new uint[](index);
        for (uint i = 0; i < index; i++) {
            tokenIds_[i] = tmp[i];
        }
    }

    function pause() onlyOwner public {
        _pause();
    }

    function unpause() onlyOwner public {
        _unpause();
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

    function pullNFTs(address tokenAddress, address receivedAddress, uint amount) onlyOwner external {
        require(receivedAddress != address(0));
        require(tokenAddress != address(0));
        require(tokenAddress != address(nftToken), "Pulling staked NFT tokens are not allowed");
        uint balance = IERC721(tokenAddress).balanceOf(address(this));
        if (balance < amount) {
            amount = balance;
        }
        for (uint i = 0; i < amount; i++) {
            uint tokenId = IERC721Enumerable(tokenAddress).tokenOfOwnerByIndex(address(this), 0);
            IERC721(tokenAddress).safeTransferFrom(address(this), receivedAddress, tokenId);
        }
    }
}