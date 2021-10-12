// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";


contract DefinaCard721 is ERC721Enumerable, ERC721URIStorage, Initializable {
    // for inherit
    function _burn (uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        ERC721URIStorage._burn(tokenId);
    }
    function _beforeTokenTransfer (address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        ERC721Enumerable._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return interfaceId == type(IERC721).interfaceId
        || interfaceId == type(IERC721Enumerable).interfaceId
        || interfaceId == type(IERC721Metadata).interfaceId
        || super.supportsInterface(interfaceId);
    }


    using SafeMath for uint;
    using Address for address;
    using Strings for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    address public Admin;
    mapping(address => mapping(uint => uint)) public minters;
    address public superMinter;

    event SetAdmin(address _new);
    event SetSuperMinter(address _new);
    event SetMinter(address _new, uint cardId_, uint amount_);
    event SetBlindBox(address _new);
    event Mint(uint cardId_);
    event MintMulti(uint cardId_, uint _amount);
    event NewCard(string name_, uint cardId_, uint camp_, uint rarity_,
        uint maxAmount_, string cardURI_);
    event Burn(uint indexed tokenId_);
    event PullNFTs(address tokenAddress_, address receivedAddress_, uint amount_);


    modifier onlyAdmin () {
        require(_msgSender() == Admin, "not Admin's calling");
        _;
    }

    function setAdmin(address newAdmin_) external onlyAdmin {
        require(newAdmin_ != address(0), "The address is null");
        Admin = newAdmin_;
        emit SetAdmin(newAdmin_);
    }

    function setSuperMinter(address newSuperMinter_) external onlyAdmin {
        require(newSuperMinter_ != address(0), "The address is null");
        superMinter = newSuperMinter_;
        emit SetSuperMinter(newSuperMinter_);
    }

    function setMinter(address newMinter_, uint cardId_, uint amount_) external onlyAdmin {
        require(newMinter_ != address(0), "The address is null");
        require(cardId_ != 0, "The cardId_ is null");
        require(amount_ != 0, "The amount_ is null");
        minters[newMinter_][cardId_] = amount_;
        emit SetMinter(newMinter_, cardId_, amount_);
    }


    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct CardInfo {
        uint cardId;
        uint camp;
        uint rarity;
        string name;
        uint currentAmount;
        uint maxAmount;
        string cardURI;
    }

    // cardId => cardInfo
    mapping(uint => CardInfo) public cardInfoes;
    EnumerableSet.UintSet private cardIds;

    // token => cardId
    mapping(uint => uint) public cardIdMap;
    string public myBaseURI;
    address public blindBox;

    constructor() ERC721("Defina Card", "DEFINACARD") {
        Admin = _msgSender();
    }

    function initialize(address blindBox_, string memory baseTokenURI_) onlyAdmin external initializer {
        setBlindBox(blindBox_);
        myBaseURI = baseTokenURI_;
    }

    function setBlindBox(address blindBox_) onlyAdmin public {
        require(blindBox_ != address(0), "The address of Blind Box token is null");
        blindBox = blindBox_;
        emit SetBlindBox(blindBox_);
    }

    function setMyBaseURI(string memory uri_) external onlyAdmin {
        myBaseURI = uri_;
    }

    function newCard(string memory name_, uint cardId_, uint camp_, uint rarity_,
        uint maxAmount_, string memory cardURI_) external onlyAdmin {

        require(cardId_ != 0 && cardInfoes[cardId_].cardId == 0, "ERC721: wrong cardId");
        cardIds.add(cardId_);
        cardInfoes[cardId_] = CardInfo({
        cardId : cardId_,
        name : name_,
        camp: camp_,
        rarity: rarity_,
        currentAmount : 0,
        maxAmount : maxAmount_,
        cardURI : cardURI_
        });
    }

    function updateCard(string memory name_, uint cardId_, uint camp_, uint rarity_,
        uint maxAmount_, string memory cardURI_) external onlyAdmin {
        require(cardId_ != 0 && cardInfoes[cardId_].cardId != 0, "ERC721: wrong cardId");
        require(maxAmount_ > cardInfoes[cardId_].currentAmount, "ERC721: maxAmount less than current amount");

        cardInfoes[cardId_].name = name_;
        cardInfoes[cardId_].camp = camp_;
        cardInfoes[cardId_].rarity = rarity_;
        cardInfoes[cardId_].maxAmount = maxAmount_;
        cardInfoes[cardId_].cardURI = cardURI_;
    }

    function mint(uint cardId_) public returns (uint256) {
        require(cardId_ != 0 && cardInfoes[cardId_].cardId != 0, "ERC721: wrong cardId");

        if (superMinter != _msgSender()) {
            require(minters[_msgSender()][cardId_] > 0, "ERC721: not minter's calling");
            minters[_msgSender()][cardId_] -= 1;
        }

        require(cardInfoes[cardId_].currentAmount < cardInfoes[cardId_].maxAmount, "ERC721: Token amount is out of limit");
        cardInfoes[cardId_].currentAmount += 1;

        _tokenIds.increment();
        uint tokenId = _tokenIds.current();
        emit Mint(cardId_);

        cardIdMap[tokenId] = cardId_;
        _mint(blindBox, tokenId);

        return tokenId;
    }

    function mintMulti(uint cardId_, uint amount_) public returns (uint256) {
        require(amount_ > 0, "ERC721: missing amount");
        require(cardId_ != 0 && cardInfoes[cardId_].cardId != 0, "ERC721: wrong cardId");

        if (superMinter != _msgSender()) {
            require(minters[_msgSender()][cardId_] >= amount_, "ERC721: not minter's calling");
            minters[_msgSender()][cardId_] -= amount_;
        }

        require(cardInfoes[cardId_].maxAmount.sub(cardInfoes[cardId_].currentAmount) >= amount_, "ERC721: Token amount is out of limit");
        cardInfoes[cardId_].currentAmount += amount_;

        uint tokenId;
        for (uint i = 0; i < amount_; ++i) {
            _tokenIds.increment();
            tokenId = _tokenIds.current();

            cardIdMap[tokenId] = cardId_;
            _mint(blindBox, tokenId);

        }
        emit MintMulti(cardId_, amount_);
        return tokenId;

    }

    function burn(uint tokenId_) public returns (bool){
        require(_isApprovedOrOwner(_msgSender(), tokenId_), "ERC721: burn caller is not owner nor approved");

        delete cardIdMap[tokenId_];
        _burn(tokenId_);
        emit Burn(tokenId_);
        return true;
    }

    function burnMulti(uint[] calldata tokenIds_) public returns (bool){
        for (uint i = 0; i < tokenIds_.length; ++i) {
            uint tokenId_ = tokenIds_[i];
            require(_isApprovedOrOwner(_msgSender(), tokenId_), "ERC721: burn caller is not owner nor approved");

            delete cardIdMap[tokenId_];
            _burn(tokenId_);
            emit Burn(tokenId_);
        }
        return true;
    }

    function tokenURI(uint256 tokenId_) override(ERC721URIStorage, ERC721) public view returns (string memory) {
        require(_exists(tokenId_), "ERC721Metadata: URI query for nonexistent token");

        string memory URI = cardInfoes[cardIdMap[tokenId_]].cardURI;
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0
        ? string(abi.encodePacked(baseURI, URI))
        : URI;
    }

    function getTokenIDsByAddress(address who) view external returns(uint[] memory) {
        require(who != address(0));
        uint length = balanceOf(who);
        uint[] memory tmp = new uint[](length);
        for (uint i = 0; i < length; i++) {
            tmp[i] = tokenOfOwnerByIndex(who, length-i-1);
        }
        return tmp;
    }

    function _baseURI() internal view override returns (string memory) {
        return myBaseURI;
    }

    function pullNFTs(address tokenAddress, address receivedAddress, uint amount) onlyAdmin public {
        require(receivedAddress != address(0));
        require(tokenAddress != address(0));
        uint balance = IERC721(tokenAddress).balanceOf(address(this));
        if (balance < amount) {
            amount = balance;
        }
        for (uint i = 0; i < amount; i++) {
            uint tokenId = IERC721Enumerable(tokenAddress).tokenOfOwnerByIndex(address(this), 0);
            IERC721(tokenAddress).safeTransferFrom(address(this), receivedAddress, tokenId);
        }
        emit PullNFTs(tokenAddress, receivedAddress, amount);
    }
}