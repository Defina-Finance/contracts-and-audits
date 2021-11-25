// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";



interface IDefinaCard{
    function mint(uint cardId_) external returns (uint256);
    function safeTransferFrom(address from, address to, uint256 tokenId ) external;

}

/**
 * @dev {ERC721} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *  - token ID and URI autogeneration
 */
contract DefinaHeroBox is
Context,
AccessControlEnumerable,
ERC721Enumerable,
ERC721Burnable,
ERC721Pausable,
ERC721Holder,
Initializable
{
    using Counters for Counters.Counter;
    using SafeMath for uint;
    using Address for address;
    using Strings for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event SetNftToken(IDefinaCard _newNft);
    event SetMyBaseURI(string _newURI);
    event Mint(address _to, uint tokenid_);
    event MintMulti(address indexed _to, uint _amount);
    event Open(uint indexed cardId_, uint indexed nftId_);

    Counters.Counter private _tokenIdTracker;
    IERC20 public currToken;
    uint public nftPrice;
    address public tokenReceiveAddress;
    mapping (uint => uint) public cardsQuota;
    EnumerableSet.UintSet private cardIds;
    mapping (uint => uint) public nftIdtoCardId;

    uint public totalBlindBoxQuota;
    uint public totalBlindBoxSold;

    EnumerableSet.AddressSet private whiteList;
    mapping (address => uint) public whitelistBuyingHistory;
    bool public whiteListOnly;
    uint public whiteListBuyableQuota;

    EnumerableSet.AddressSet private publicBuyerList;
    mapping (address => uint) public publicBuyingHistory;
    uint public publicBuyableQuota;

    string private _baseTokenURI;
    IDefinaCard public nftToken;

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "Blindbox: not eoa");
        _;
    }

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     */
    constructor() ERC721("Defina Hero Box", "HEROBOX") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    function initialize(IDefinaCard nftToken_, string memory baseTokenURI,
        IERC20 currToken_, uint nftPrice_, address tokenReceiveAddress_, uint[] calldata cardIds_,
        uint[] calldata cardsNum_)
        public initializer {
        require(hasRole(ADMIN_ROLE, _msgSender()), "BlindBox: must have admin role to initialize");
        require(cardIds_.length != 0, "BlindBox: No cardIds was provided.");
        require(cardIds_.length == cardsNum_.length, "BlindBox: Number of card ids not match card quota");
        setNftToken(nftToken_);
        _baseTokenURI = baseTokenURI;
        setCurrToken(currToken_);
        setNftPrice(nftPrice_);
        setErc20TokenReceiveAddress(tokenReceiveAddress_);
        for (uint i = 0; i < cardIds_.length; i++) {
            require(cardIds_[i] != 0);
            require(cardsNum_[i] != 0);
            cardsQuota[cardIds_[i]] = cardsNum_[i];
            cardIds.add(cardIds_[i]);
            totalBlindBoxQuota += cardsNum_[i];
        }
    }

    function setCardsQuota(uint[] calldata cardIds_,
        uint[] calldata cardsNum_) onlyRole(ADMIN_ROLE) whenPaused external {
        require(cardIds_.length != 0, "BlindBox: No cardIds was provided.");
        require(cardIds_.length == cardsNum_.length, "BlindBox: Number of card ids not match card quota");
        //remove previous quota first
        uint length = cardIds.length();
        for (uint i = 0; i < length; i++) {
            uint cardId = cardIds.at(0);
            delete cardsQuota[cardId];
            cardIds.remove(cardId);
        }
        totalBlindBoxQuota = 0;
        totalBlindBoxSold = 0;
        for (uint i = 0; i < cardIds_.length; i++) {
            require(cardIds_[i] != 0);
            require(cardsNum_[i] != 0);
            cardsQuota[cardIds_[i]] = cardsNum_[i];
            cardIds.add(cardIds_[i]);
            totalBlindBoxQuota += cardsNum_[i];
        }
    }

    function setNftPrice(uint nftPrice_) onlyRole(ADMIN_ROLE) whenPaused public {  
        require(nftPrice_ > 0, "Price should not be 0");
        nftPrice = nftPrice_;
    }

    function setErc20TokenReceiveAddress(address tokenReceiveAddress_) onlyRole(ADMIN_ROLE) whenPaused public {
        require(tokenReceiveAddress_ != address(0), "The address of receive is null");
        tokenReceiveAddress = tokenReceiveAddress_;
    }

    function setCurrToken(IERC20 currToken_) onlyRole(ADMIN_ROLE) whenPaused public {
        require(currToken_ != IERC20(address(0)), "The address of IERC20 token is null");
        currToken = currToken_;
    }

    function transferAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(DEFAULT_ADMIN_ROLE, account);
        revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    
    function setNftToken(IDefinaCard nftToken_) onlyRole(ADMIN_ROLE) whenPaused public {
        require(nftToken_ != IDefinaCard(address(0)), "The address of IERC721 token is null");
        nftToken = nftToken_;
        emit SetNftToken(nftToken_);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setMyBaseURI(string memory uri_) onlyRole(ADMIN_ROLE) whenPaused external {
        _baseTokenURI = uri_;
        emit SetMyBaseURI(uri_);
    }

    function _randModulus(uint mod) internal view returns (uint) {
        uint rand = uint(keccak256(abi.encodePacked(
                block.timestamp,
                block.difficulty,
                _msgSender())
            )) % mod;
        return rand;
    }

    function setWhiteListBuyableQuota(uint whiteListBuyableQuota_) onlyRole(ADMIN_ROLE) whenPaused external {
        whiteListBuyableQuota = whiteListBuyableQuota_;
    }

    function setPublicBuyableQuota(uint publicBuyableQuota_) onlyRole(ADMIN_ROLE) whenPaused external {
        publicBuyableQuota = publicBuyableQuota_;
    }

    function toggleWhiteListOnly() onlyRole(ADMIN_ROLE) whenPaused external {
        if (whiteListOnly) {
            whiteListOnly = false;
        } else {
            whiteListOnly = true;
        }
    }

    function containsInWhiteList(address candidate_) public view returns (bool) {
        return whiteList.contains(candidate_);
    }

    function whiteListCount() public view returns (uint) {
        return whiteList.length();
    }

    function whiteListAtIndex(uint index) public view returns (address) {
        require(index < whiteList.length(), "DefinaNFTMarket:: index out of bounds");
        return whiteList.at(index);
    }

    function addToWhitelist(address[] calldata candidates_) onlyRole(ADMIN_ROLE) whenPaused external returns (bool) {
        require(candidates_.length > 0, "The length is 0");
        for(uint i = 0; i < candidates_.length; i++){
            require(candidates_[i] != address(0));
            whiteList.add(candidates_[i]);
        }
        return true;
    }

    function cleanWhitelist(uint amount) onlyRole(ADMIN_ROLE) whenPaused public returns (bool) {
        uint length = whiteList.length();
        if (length < amount) {
            amount = length;
        }
        for(uint i = 0; i < amount; i++) {
            // modify fix 0 position while iterating all keys
            address candidate = whiteList.at(0);
            delete whitelistBuyingHistory[candidate];
            whiteList.remove(candidate);
        }
        return true;
    }

    function cleanPublicBuyHistory(uint amount) onlyRole(ADMIN_ROLE) whenPaused public returns (bool) {
        uint length = publicBuyerList.length();
        if (length < amount) {
            amount = length;
        }
        for (uint i = 0; i < amount; i++) {
            // modify fix 0 position while iterating all keys
            address buyer = publicBuyerList.at(0);
            delete publicBuyingHistory[buyer];
            publicBuyerList.remove(buyer);
        }
        return true;
    }

    function mintMulti(uint amount) whenNotPaused onlyEOA external {
        require(amount > 0, "BlindBox: missing amount");
        totalBlindBoxSold += amount;
        require(totalBlindBoxSold <= totalBlindBoxQuota, "BindBox: exceeded total blind box buyable quota.");

        if (whiteListOnly) {
            require(whiteList.contains(_msgSender()),"only whitelist allowed");
            require(whitelistBuyingHistory[_msgSender()] + amount <= whiteListBuyableQuota,"Out of whitelist quota");
            whitelistBuyingHistory[_msgSender()] += amount;
        } else {
            require(publicBuyingHistory[_msgSender()] + amount <= publicBuyableQuota, "Out of public sell quota");
            publicBuyingHistory[_msgSender()] += amount;
            publicBuyerList.add(_msgSender());
        }

        for (uint i = 0; i < amount; i++) {
            _mint(_msgSender(), _tokenIdTracker.current());
            emit Mint(_msgSender(),_tokenIdTracker.current());
            _tokenIdTracker.increment();
        }
        uint cost = nftPrice.mul(amount);
        IERC20(currToken).safeTransferFrom(_msgSender(), tokenReceiveAddress, cost);
        emit MintMulti(_msgSender(), amount);
    }

    function open(uint tokenId) whenNotPaused onlyEOA external {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "BlindBox: caller is not owner nor approved");
        burn(tokenId);
        uint index = _randModulus(cardIds.length());
        uint cardId = cardIds.at(index);
        cardsQuota[cardId] -= 1;
        if (cardsQuota[cardId] == 0) {
            delete cardsQuota[cardId];
            cardIds.remove(cardId);
        }
        uint nftId = nftToken.mint(cardId);
        nftToken.safeTransferFrom(address(this), _msgSender(), nftId);
        nftIdtoCardId[nftId] = cardId;
        emit Open(cardId,nftId);
    }

    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "BlindBox: must have pauser role to pause");
        _pause();
    }

    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "BlindBox: must have pauser role to unpause");
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable, ERC721Pausable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControlEnumerable, ERC721, ERC721Enumerable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function pullNFTs(address tokenAddress, address receivedAddress, uint amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
    }
}
