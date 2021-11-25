// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

interface IDefinaCard {
    function mint(uint cardId_) external returns (uint256);
    function safeTransferFrom(address from, address to, uint256 tokenId ) external;
}

interface IDefinaHeroBox {
    function setCardsQuota(uint[] calldata cardIds_, uint[] calldata cardsNum_)  external;
}

/**
 * @dev {ERC721} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *  - token ID and URI autogeneration
 */
contract DefinaCardAdapter is
Context,
AccessControlEnumerable,
Initializable
{
    using Address for address;
    using Strings for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event SetNftToken(address _newNft);
    event SetBlindBox(address _blindBox);
    event Open(uint indexed cardId_, uint indexed nftId_);

    uint public totalCardNum;

    address public nftToken;
    address public blindBox;

    struct CardPair {
        uint cardId;
        uint cardsNum;
    }

    CardPair[] public cardPairs;

    modifier onlyBlindBox() {
        require(msg.sender == blindBox, "DefinaCardAdapter: only blind box");
        _;
    }

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     */
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    function initialize(address nftToken_, address blindBox_)
        public initializer {
        require(hasRole(ADMIN_ROLE, _msgSender()), "DefinaCardAdapter: must have admin role to initialize");
        setNftToken(nftToken_);
        setBlindBox(blindBox_);
    }

    function setCardsQuota(uint[] calldata cardIds_, uint[] calldata cardsNum_) onlyRole(ADMIN_ROLE)  external {
        require(cardIds_.length != 0, "DefinaCardAdapter: No cardIds was provided.");
        require(cardIds_.length == cardsNum_.length, "DefinaCardAdapter: Number of card ids not match card quota");
        //remove previous quota first

        delete cardPairs;
        totalCardNum = 0;
        for (uint i = 0; i < cardIds_.length; i++) {
            require(cardIds_[i] != 0);
            require(cardsNum_[i] != 0);
            CardPair memory cardPair = CardPair({
                cardId: cardIds_[i],
                cardsNum: cardsNum_[i]
            });
            totalCardNum += cardsNum_[i];
            cardPairs.push(cardPair);
        }
        IDefinaHeroBox heroBox = IDefinaHeroBox(blindBox);
        heroBox.setCardsQuota(cardIds_, cardsNum_);
    }

    function mint(uint cardId_) onlyBlindBox external returns (uint256) {
        require(totalCardNum > 0, "DefinaCardAdapter: no card left");
        uint r = _randModulus(totalCardNum);
        uint index = 0;
        for (uint i = 0; i < cardPairs.length; i++) {
            if (cardPairs[i].cardsNum <= 0) {
                continue;
            }
            if (r <= cardPairs[i].cardsNum) {
                index = i;
                break;
            }
           r -= cardPairs[i].cardsNum;
        }
        CardPair storage selectedCard = cardPairs[index];
        selectedCard.cardsNum -= 1;
        totalCardNum -= 1;
        uint nftId = IDefinaCard(nftToken).mint(selectedCard.cardId);
        emit Open(selectedCard.cardId, nftId);

        return nftId;
    }

    function transferAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(DEFAULT_ADMIN_ROLE, account);
        revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    
    function setNftToken(address nftToken_) onlyRole(ADMIN_ROLE)  public {
        require(nftToken_ != address(0), "The address of IERC721 token is null");
        nftToken = nftToken_;
        emit SetNftToken(nftToken_);
    }

    function setBlindBox(address blindBox_) onlyRole(ADMIN_ROLE)  public {
        require(blindBox_ != address(0), "The address of IERC721 token is null");
        blindBox = blindBox_;
        emit SetBlindBox(blindBox_);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId ) onlyBlindBox external {
        IDefinaCard(nftToken).safeTransferFrom(address(this), to, tokenId);
    }

    function _randModulus(uint mod) internal view returns (uint) {
        uint rand = uint(keccak256(abi.encodePacked(
                block.timestamp,
                block.difficulty,
                _msgSender())
            )) % mod;
        return rand;
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControlEnumerable)
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
