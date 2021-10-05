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

/**
 * @dev {ERC721} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *  - token ID and URI autogeneration
 */
contract BlindBox is
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
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event SetNftToken(IERC721Enumerable _newNft);
    event SetMyBaseURI(string _newURI);
    event Mint(address _to);
    event MintMulti(address indexed _to, uint _amount);
    event Open(uint indexed tokenId_);

    Counters.Counter private _tokenIdTracker;

    string private _baseTokenURI;

    IERC721Enumerable public nftToken;
    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     */
    constructor() ERC721("Defina Blind Box", "DEFINABLINDBOX") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    function initialize(IERC721Enumerable nftToken_, string memory baseTokenURI) public initializer {
        require(hasRole(ADMIN_ROLE, _msgSender()), "BlindBox: must have admin role to initialize");
        setNftToken(nftToken_);
        _baseTokenURI = baseTokenURI;
    }

    function transferAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(DEFAULT_ADMIN_ROLE, account);
        revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    
    function setNftToken(IERC721Enumerable nftToken_) onlyRole(ADMIN_ROLE) whenPaused public {
        require(nftToken_ != IERC721Enumerable(address(0)), "The address of IERC721 token is null");
        nftToken = nftToken_;
        emit SetNftToken(nftToken_);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setMyBaseURI(string memory uri_) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "BlindBox: must have admin role to change base uri");
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

    function mint(address to) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "BlindBox: must have minter role to mint");

        // We cannot just use balanceOf to create the new tokenId because tokens
        // can be burned (destroyed), so we need a separate counter.
        _mint(to, _tokenIdTracker.current());
        _tokenIdTracker.increment();
        emit Mint(to);
    }

    function mintMulti(address to, uint amount) external {
        require(amount > 0, "BlindBox: missing amount");
        require(hasRole(MINTER_ROLE, _msgSender()), "BlindBox: must have minter role to mint");

        for (uint i = 0; i < amount; ++i) {
            _mint(to, _tokenIdTracker.current());
            _tokenIdTracker.increment();
        }
        emit MintMulti(to, amount);
    }

    function open(uint256 tokenId) whenNotPaused external {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "BlindBox: caller is not owner nor approved");
        burn(tokenId);
        uint totalNftNum = nftToken.balanceOf(address(this));

        uint nftId = nftToken.tokenOfOwnerByIndex(address(this), _randModulus(totalNftNum));
        nftToken.safeTransferFrom(address(this), _msgSender(), nftId);
        emit Open(tokenId);
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
