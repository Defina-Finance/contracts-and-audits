// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

interface IDefinaCard{
    function mint(uint cardId_) external returns (uint256);
    function safeTransferFrom(address from, address to, uint256 tokenId ) external;

}

interface IRandomGenerator {
    function requestRandomNumber(uint256 tokenId, address user) external;
}
/**
 * @dev {ERC721} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *  - token ID and URI auto-generation
 */
contract DefinaHeroBoxV2 is
Initializable,
ContextUpgradeable,
AccessControlEnumerableUpgradeable,
ERC721EnumerableUpgradeable,
ERC721BurnableUpgradeable,
ERC721PausableUpgradeable,
ERC721HolderUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address;
    using StringsUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");


    event SetRandomGenerator(IRandomGenerator _newRandomGenerator);
    event SetNftToken(IDefinaCard _newNft);
    event SetMyBaseURI(string _newURI);
    event Mint(address _to, uint tokenid_);
    event MintMulti(address indexed _to, uint _amount);
    event OpenRequested(uint indexed tokenId, address indexed user_);
    event Open(uint indexed tokenId_, uint indexed cardId_, uint indexed nftId_);

    CountersUpgradeable.Counter private _tokenIdTracker;
    IERC20Upgradeable public currToken;
    uint public nftPrice;
    address public tokenReceiveAddress;
    mapping (uint => uint) public cardsQuota;
    mapping (uint => uint) private cardsRemaining;
    mapping (uint => uint) private cardsRatio;
    EnumerableSetUpgradeable.UintSet private cardIds;
    mapping (uint => uint) public nftIdtoCardId; // TODO: to be removed

    uint public totalBlindBoxQuota;
    uint public totalBlindBoxSold;
    uint public totalBlindBoxRemaining;

    EnumerableSetUpgradeable.AddressSet private whiteList;
    mapping (address => uint) public whitelistBuyingHistory;
    bool public whiteListOnly;
    uint public whiteListBuyableQuota;

    EnumerableSetUpgradeable.AddressSet private publicBuyerList;
    mapping (address => uint) public publicBuyingHistory;
    uint public publicBuyableQuota;

    string private _baseTokenURI;
    IDefinaCard public nftToken;

    IRandomGenerator public randomGenerator;

    uint[] private allCandidateCards; // TODO: to be removed in final version
    uint private INVALID_CARD_ID;
    mapping (uint => uint) private cardsRatioRange;


    modifier onlyEOA() {
        require(msg.sender == tx.origin, "Blindbox: not eoa");
        _;
    }

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     */
    constructor() {}

    function initialize(IDefinaCard nftToken_, string memory baseTokenURI,
        IERC20Upgradeable currToken_, uint nftPrice_, address tokenReceiveAddress_, uint[] calldata cardIds_,
        uint[] calldata cardsNum_, IRandomGenerator randomGenerator_)
        public initializer {
        __AccessControlEnumerable_init();
        __ERC721_init_unchained("Defina Hero Box", "HEROBOX");
        __ERC721Enumerable_init_unchained();
        __ERC721Burnable_init_unchained();
        __Pausable_init_unchained();
        __ERC721Pausable_init_unchained();
        __ERC721Holder_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());

        require(hasRole(ADMIN_ROLE, _msgSender()), "BlindBox: must have admin role to initialize");
        require(cardIds_.length != 0, "BlindBox: No cardIds was provided.");
        require(cardIds_.length == cardsNum_.length, "BlindBox: Number of card ids not match card quota");

        nftToken = nftToken_;
        _baseTokenURI = baseTokenURI;
        currToken = currToken_;
        nftPrice = nftPrice_;
        tokenReceiveAddress = tokenReceiveAddress_;
        randomGenerator = randomGenerator_;
        for (uint i = 0; i < cardIds_.length; i++) {
            require(cardIds_[i] != 0);
            require(cardsNum_[i] != 0);
            cardsQuota[cardIds_[i]] = cardsNum_[i];
            cardsRemaining[cardIds_[i]] = cardsNum_[i];
            cardIds.add(cardIds_[i]);
            totalBlindBoxQuota += cardsNum_[i];
        }

        for (uint i = 0; i < cardIds_.length; i++) {
            cardsRatio[cardIds_[i]] = cardsQuota[cardIds_[i]] * 1e12 / totalBlindBoxQuota;
            cardsRatioRange[cardIds_[i]] = cardsRatio[cardIds_[i]] * 10 / 100;
        }
        totalBlindBoxRemaining = totalBlindBoxQuota;
        INVALID_CARD_ID = type(uint).max;
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
            delete cardsRatio[cardId];
            cardIds.remove(cardId);
        }
        totalBlindBoxQuota = 0;
        totalBlindBoxSold = 0;
        for (uint i = 0; i < cardIds_.length; i++) {
            require(cardIds_[i] != 0);
            require(cardsNum_[i] != 0);
            cardsQuota[cardIds_[i]] = cardsNum_[i];
            cardsRemaining[cardIds_[i]] = cardsNum_[i];
            cardIds.add(cardIds_[i]);
            totalBlindBoxQuota += cardsNum_[i];
        }

        for (uint i = 0; i < cardIds_.length; i++) {
            cardsRatio[cardIds_[i]] = cardsQuota[cardIds_[i]] * 1e12 / totalBlindBoxQuota;
            cardsRatioRange[cardIds_[i]] = cardsRatio[cardIds_[i]] * 10 / 100;
        }
        totalBlindBoxRemaining = totalBlindBoxQuota;
    }

    function setRandomGenerator(IRandomGenerator randomGenerator_) onlyRole(ADMIN_ROLE) whenPaused public {
        require(randomGenerator_ != IRandomGenerator(address(0)), "The address of random generator is null");
        randomGenerator = randomGenerator_;
        emit SetRandomGenerator(randomGenerator_);
    }

    function setNftPrice(uint nftPrice_) onlyRole(ADMIN_ROLE) whenPaused public {  
        require(nftPrice_ > 0, "Price should not be 0");
        nftPrice = nftPrice_;
    }

    function setErc20TokenReceiveAddress(address tokenReceiveAddress_) onlyRole(ADMIN_ROLE) whenPaused public {
        require(tokenReceiveAddress_ != address(0), "The address of receive is null");
        tokenReceiveAddress = tokenReceiveAddress_;
    }

    function setCurrToken(IERC20Upgradeable currToken_) onlyRole(ADMIN_ROLE) whenPaused public {
        require(currToken_ != IERC20Upgradeable(address(0)), "The address of IERC20 token is null");
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

    function _randModulus(address user, uint seed, uint nonce, uint mod) internal view returns (uint) {
        uint rand = uint(keccak256(abi.encodePacked(
                block.timestamp,
                block.difficulty,
                mod,
                user,
                seed,
                nonce,
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
        uint cost = nftPrice * amount;
        IERC20Upgradeable(currToken).safeTransferFrom(_msgSender(), tokenReceiveAddress, cost);
        emit MintMulti(_msgSender(), amount);
    }

    function open(uint tokenId) whenNotPaused onlyEOA external {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "BlindBox: caller is not owner nor approved");
        randomGenerator.requestRandomNumber(tokenId, _msgSender());
        approve(address(randomGenerator), tokenId);
        emit OpenRequested(tokenId, _msgSender());
    }

    function runFulfillRandomness(uint256 tokenId_, address user_, uint256 randomness_) external {
        require(_msgSender() == address(randomGenerator),
            "BlindBox: only selected generator can call this method"
        );
        fulfillRandomness(tokenId_, user_, randomness_);
    }

    function indexToCardId(uint index_) private view returns (uint){
        uint length = cardIds.length();
        uint cardId;
        for (uint i = 0; i < length; i++) {
            cardId = cardIds.at(i);
            if (cardsRemaining[cardId] <= 0) {
                continue;
            }
            if (index_ < cardsRemaining[cardId]) {
                break;
            }
            index_ -= cardsRemaining[cardId];
        }
        return cardId;
    }

    function fulfillRandomness(uint256 tokenId, address user, uint256 randomness) internal {
        require(_isApprovedOrOwner(user, tokenId), "BlindBox: caller is not owner nor approved");
        burn(tokenId);
        uint i = 3;   // max retry
        uint cardId = INVALID_CARD_ID;
        do {
            cardId = indexToCardId(_randModulus(user, randomness, i, totalBlindBoxRemaining));

            uint curRatio = cardsRemaining[cardId] * 1e12 / totalBlindBoxRemaining;

            if (curRatio + cardsRatioRange[cardId] >= cardsRatio[cardId]) {
                break;
            }
            i -= 1;
        } while (i > 0);

        assert(cardId != INVALID_CARD_ID);

        cardsRemaining[cardId] -= 1;
        totalBlindBoxRemaining -= 1;

        uint nftId = nftToken.mint(cardId);
        nftToken.safeTransferFrom(address(this), user, nftId);
        emit Open(tokenId, cardId, nftId);
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
    ) internal virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControlEnumerableUpgradeable, ERC721Upgradeable, ERC721EnumerableUpgradeable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function pullNFTs(address tokenAddress, address receivedAddress, uint amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(receivedAddress != address(0));
        require(tokenAddress != address(0));
        uint balance = IERC721Upgradeable(tokenAddress).balanceOf(address(this));
        if (balance < amount) {
            amount = balance;
        }
        for (uint i = 0; i < amount; i++) {
            uint tokenId = IERC721EnumerableUpgradeable(tokenAddress).tokenOfOwnerByIndex(address(this), 0);
            IERC721Upgradeable(tokenAddress).safeTransferFrom(address(this), receivedAddress, tokenId);
        }
    }
}
