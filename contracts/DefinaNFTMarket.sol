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


contract DefinaNFTMarket is Ownable, IERC721Receiver, Initializable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    event NFTDeposit(address indexed _who, address indexed _tokenAddress, uint indexed _tokenId, uint _grade, uint nftId);
    event NFTWithdraw(address indexed _who, address indexed _tokenAddress, uint indexed _tokenId, uint _grade, uint nftId);
    event SelectedNFTs(address indexed _who, uint[]);
    event BuyingBox(address indexed _who, uint boxSize);
    event OutOfStock(address indexed _who, uint _requestedNum, uint _stockNum);
    event PreSellWhiteListOnly();
    event OpenToPublicSell();
    event HasReset();

    IERC20 public currToken;
    address public tokenReceiveAddress;

    uint public nextNFTId;

    struct NFT {
        address tokenAddress;
        uint tokenId;
        address owner;
        uint grade;
    }

    // nftId => NFT
    mapping(uint => NFT) public allNFTs;

    // owner => nftId[]
    mapping(address => uint[]) public nftsByOwner;
    mapping(address => uint[]) public lastOrderByOwner;

    // tokenAddress => tokenId => nftId
    mapping(address => mapping(uint => uint)) public nftIdMap;

    // grade => nftId[]
    mapping(uint => uint[]) public nftsByGradeForSell;
    mapping(uint => uint[]) public nftsByGradeSold;

    uint[] public nftsGrades;
    uint[] private nftsGradesReverse;

    EnumerableSet.UintSet private _supportedBoxSizes;

    uint public nftPrice;

    uint public startTime = 0;

    mapping (address => uint) public whitelistBuyingHistory;
    EnumerableSet.AddressSet private whiteList;
    uint public whiteListBuyableQuota;
    bool public whiteListOnly;

    mapping (address => uint) publicBuyingHistory;
    EnumerableSet.AddressSet private publicBuyerList;
    uint public publicBuyableQuota;

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "ForceNFTMarket: not eoa");
        _;
    }

    constructor() {}

    function setWhiteListBuyableQuota(uint whiteListBuyableQuota_) onlyOwner whenPaused external {
        whiteListBuyableQuota = whiteListBuyableQuota_;
    }

    function setPublicBuyableQuota(uint publicBuyableQuota_) onlyOwner whenPaused external {
        publicBuyableQuota = publicBuyableQuota_;
    }

    function toggleWhiteListOnly() onlyOwner whenPaused external {
        if (whiteListOnly) {
            whiteListOnly = false;
            emit OpenToPublicSell();
        } else {
            whiteListOnly = true;
            emit PreSellWhiteListOnly();
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

    function addToWhitelist(address[] calldata candidates_) onlyOwner whenPaused external returns (bool) {
        require(candidates_.length > 0, "The length is 0");

        for(uint i = 0; i < candidates_.length; i++){
            require(candidates_[i] != address(0));
            whiteList.add(candidates_[i]);
        }

        return true;
    }

    /**
     * @dev clean the whitelist
     */
    function cleanWhitelist(uint amount) onlyOwner whenPaused public returns (bool) {
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
        require(whiteList.length() == 0);

        return true;
    }

    function setStartTime(uint startTime_) onlyOwner whenPaused external {
        startTime = startTime_;
    }

    function onERC721Received(address, address, uint, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function nftsByGradeForSellCount(uint grade_) external view returns(uint count) {
       count = nftsByGradeForSell[grade_].length;
    }

    function nftsByGradeSoldCount(uint grade_) external view returns(uint count) {
        count = nftsByGradeSold[grade_].length;
    }

    function nftsGradesCount() external view returns(uint count) {
        count = nftsGrades.length;
    }

    function nftsByOwnerCount(address ownerAddress_) external view returns(uint count) {
        count = nftsByOwner[ownerAddress_].length;
    }

    function containsSupportedBoxSize(uint boxSize_) public view returns (bool) {
        return _supportedBoxSizes.contains(boxSize_);
    }

    function SupportedBoxSizesCount() public view returns (uint) {
        return _supportedBoxSizes.length();
    }

    function supportedBoxSizeAtIndex(uint index) public view returns (uint) {
        require(index < _supportedBoxSizes.length(), "ForceNFTMarket: index out of bounds");
        return _supportedBoxSizes.at(index);
    }

    function setNftPrice(uint nftPrice_) onlyOwner whenPaused public {
        require(nftPrice_ > 0, "Price should not be 0");
        nftPrice = nftPrice_;
    }

    function setErc20TokenReceiveAddress(address tokenReceiveAddress_) onlyOwner whenPaused public {
        require(tokenReceiveAddress_ != address(0), "The address of receive is null");
        tokenReceiveAddress = tokenReceiveAddress_;
    }

    function setCurrToken(IERC20 currToken_) onlyOwner whenPaused public {
        require(currToken_ != IERC20(address(0)), "The address of IERC20 token is null");
        currToken = currToken_;
    }

    function setSupportedBoxSizes(uint[] memory supportedBoxSizes_) onlyOwner whenPaused public {
        uint length = _supportedBoxSizes.length();
        for (uint i = 0; i < length; i++) {
            _supportedBoxSizes.remove(_supportedBoxSizes.at(0));
        }
        for (uint i = 0; i < supportedBoxSizes_.length; i++) {
            _supportedBoxSizes.add(supportedBoxSizes_[i]);
        }
    }

    function setNftsGrades(uint[] memory nftsGrades_) onlyOwner whenPaused public {
        require(nftsGrades_.length > 0, "Array's length is 0");
        for (uint i = 0; i < nftsGrades_.length-1; i++) {
            require(nftsGrades_[i] < nftsGrades_[i+1], "NFT grades array must be in ascending order.");
        }
        nftsGrades = nftsGrades_;
        while (nftsGradesReverse.length != 0) {
            nftsGradesReverse.pop();
        }
        for (uint i = 0; i< nftsGrades_.length; i++) {
            nftsGradesReverse.push(nftsGrades_[nftsGrades_.length - 1 - i]);
        }
    }

    function pause() onlyOwner external {
        _pause();
    }

    function unpause() onlyOwner external {
        _unpause();
    }

    function initialize(IERC20 currToken_, uint nftPrice_, address tokenReceiveAddress_,
        uint[] memory supportedBoxSizes_, uint[] memory nftsGrades_) onlyOwner external initializer {
        require(supportedBoxSizes_.length > 0, "The box size cannot be empty");
        setCurrToken(currToken_);
        setNftPrice(nftPrice_);
        setErc20TokenReceiveAddress(tokenReceiveAddress_);
        setNftsGrades(nftsGrades_);
        setSupportedBoxSizes(supportedBoxSizes_);
    }

    function reset() onlyOwner whenPaused external {
        for (uint i = 0; i < nftsGrades.length; i ++) {
           delete nftsByGradeForSell[nftsGrades[i]];
        }
        uint length = publicBuyerList.length();

        for (uint i = 0; i < length; i++) {
            // modify fix 0 position while iterating all keys
            address buyer = publicBuyerList.at(0);

            delete publicBuyingHistory[buyer];

            publicBuyerList.remove(buyer);
        }
        require(publicBuyerList.length() == 0);
        require(cleanWhitelist(whiteList.length()));

        emit HasReset();

    }

    function _generateNextNFTId() internal returns(uint) {
        return ++nextNFTId;
    }

    function deposit(address tokenAddress_, uint[] memory tokenIds_, uint[] memory tokenGrades_) onlyOwner whenPaused external {
        require(tokenAddress_ != address(0), "The address of IERC721 token is null");
        require(tokenIds_.length > 0, "The length is 0");
        require(tokenIds_.length == tokenGrades_.length, "Value lengths do not match.");
        for (uint i = 0; i < tokenIds_.length; i++) {
            require(IERC721(tokenAddress_).ownerOf(tokenIds_[i]) == address(this), "Some tokenId are not owned by the contract");
            uint nftId = _generateNextNFTId();
            allNFTs[nftId].tokenAddress = tokenAddress_;
            allNFTs[nftId].tokenId = tokenIds_[i];
            allNFTs[nftId].grade = tokenGrades_[i];

            nftsByGradeForSell[tokenGrades_[i]].push(nftId);
            nftIdMap[tokenAddress_][tokenIds_[i]] = nftId;

            emit NFTDeposit(_msgSender(), tokenAddress_, tokenIds_[i], tokenGrades_[i], nftId);
        }
    }

    function buy(uint boxSize) whenNotPaused onlyEOA external returns(uint[] memory selectedNftIds) {

        require(block.timestamp > startTime, "The sell has not started.");
        require(boxSize > 0, "box size is 0");
        require(_supportedBoxSizes.contains(boxSize), "Unsupported box size");
        if (whiteListOnly) {
            require(containsInWhiteList(_msgSender()), "The buyer is not listed in the white list");
            require(whitelistBuyingHistory[_msgSender()] + boxSize <= whiteListBuyableQuota, "Out of white list quota");
        } else {
            require(publicBuyingHistory[_msgSender()] + boxSize <= publicBuyableQuota, "Out of public sell quota");
        }

        emit BuyingBox(_msgSender(), boxSize);

        uint[] memory lowNftIds;
        uint[] memory highNftIds;

        if (boxSize == 1) {
            lowNftIds = getAvailableNftIds(1, false);
        } else {
            highNftIds = getAvailableNftIds(1, true);
            lowNftIds = getAvailableNftIds(boxSize - highNftIds.length, false);
        }
        selectedNftIds = new uint[](lowNftIds.length + highNftIds.length);
        for (uint i = 0; i < lowNftIds.length; i++) {
            selectedNftIds[i] = lowNftIds[i];
        }
        for (uint i = 0; i < highNftIds.length; i++) {
            selectedNftIds[lowNftIds.length + i] = highNftIds[i];
        }

        emit SelectedNFTs(_msgSender(), selectedNftIds);

        if (whiteListOnly) {
            uint boughtCount = whitelistBuyingHistory[_msgSender()];
            whitelistBuyingHistory[_msgSender()] = boughtCount + selectedNftIds.length;
        } else {
            uint boughtCount = publicBuyingHistory[_msgSender()];
            publicBuyingHistory[_msgSender()] = boughtCount + selectedNftIds.length;
            publicBuyerList.add(_msgSender());
        }

        delete lastOrderByOwner[_msgSender()];
        for (uint i = 0; i < selectedNftIds.length; i++) {
            uint _nftId = selectedNftIds[i];
            address tokenAddress = allNFTs[_nftId].tokenAddress;
            uint tokenId = allNFTs[_nftId].tokenId;

            emit NFTWithdraw(_msgSender(), tokenAddress, tokenId, allNFTs[_nftId].grade, _nftId);

            IERC721(tokenAddress).safeTransferFrom(address(this), _msgSender(), tokenId);
            nftsByOwner[_msgSender()].push(_nftId);
            lastOrderByOwner[_msgSender()].push(_nftId);
            allNFTs[_nftId].owner = _msgSender();
        }

        uint cost = nftPrice.mul(boxSize);
        IERC20(currToken).safeTransferFrom(_msgSender(), tokenReceiveAddress, cost);

        return selectedNftIds;
    }

    function getAvailableNftIds(uint numNfts_, bool fromHighestGrade_) internal returns(uint[] memory availableNftIds) {
        availableNftIds = new uint[](numNfts_);
        uint[] storage _nftsGrades = nftsGrades;
        if (fromHighestGrade_) {
           _nftsGrades = nftsGradesReverse;
        }
        uint numAvailableNfts;
        for (uint i = 0; i < numNfts_; i++) {
            for (uint j = 0; j < _nftsGrades.length; j++) {
                uint[] storage nftIdsForSell = nftsByGradeForSell[_nftsGrades[j]];
                if (nftIdsForSell.length == 0) {
                    continue;
                }
                uint selectedNftId = nftIdsForSell[nftIdsForSell.length - 1];
                nftIdsForSell.pop();

                availableNftIds[i] = selectedNftId;
                nftsByGradeSold[_nftsGrades[j]].push(selectedNftId);

                numAvailableNfts++;
                break;
            }
        }

        if (numAvailableNfts != numNfts_) {
            emit OutOfStock(_msgSender(), numNfts_, numAvailableNfts);
            revert("Not enough NFTs");
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

    function pullNFTs(address tokenAddress, address receivedAddress, uint amount) onlyOwner external {
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

    function shuffle() onlyOwner external {
        for (uint i = 0; i < nftsGrades.length; i++) {
            uint[] storage nftIds = nftsByGradeForSell[nftsGrades[i]];
            for (uint j = 0; j < nftIds.length; j++) {
                uint n = j + uint(keccak256(abi.encodePacked(block.timestamp))) % (nftIds.length - j);
                uint temp = nftIds[n];
                nftIds[n] = nftIds[j];
                nftIds[j] = temp;
            }
        }
    }

    function lastOrderDetail(address ownerAddress_) external view returns(NFT[] memory lastOrderNFTs) {
        uint[] storage nftIds = lastOrderByOwner[ownerAddress_];
        lastOrderNFTs = new NFT[](nftIds.length);
        for (uint i = 0; i < nftIds.length; i++) {
            lastOrderNFTs[i] = allNFTs[nftIds[i]];
        }
    }

    function nftsByOwnerDetail(address ownerAddress_) external view returns(NFT[] memory nftsOfOwner) {
        uint[] storage nftIds = nftsByOwner[ownerAddress_];
        nftsOfOwner = new NFT[](nftIds.length);
        for (uint i = 0; i < nftIds.length; i++) {
            nftsOfOwner[i] = allNFTs[nftIds[i]];
        }
    }
}