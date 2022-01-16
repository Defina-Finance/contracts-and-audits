// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRandomConsumer {
    function runFulfillRandomness(uint256 tokenId_, address user_, uint256 randomness_) external;
}

contract RandomGenerator is AccessControlEnumerable, VRFConsumerBase {
    bytes32 public constant RND_CONSUMER_ROLE = keccak256("CONSUMER_ROLE");
    struct RandomRequest {
        address requester;
        address user;
        uint tokenId;
    }

    mapping(bytes32 => RandomRequest) private _requestIdToRequest;

    bytes32 internal keyHash;
    uint256 internal fee;

    constructor(address vrfCoordinator_, address link_, bytes32 keyHash_, uint256 fee_)
    VRFConsumerBase(vrfCoordinator_, link_) {
        keyHash = keyHash_;
        fee = fee_;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function requestRandomNumber(uint256 tokenId_, address user_) public {
        require(hasRole(RND_CONSUMER_ROLE, _msgSender()), "RandomGenerator: must have consumer role to request");
        require(LINK.balanceOf(address(this)) >= fee, "RandomGenerator: not enough LINK");
        require(user_ != address(0), "RandomGenerator: no user");

        bytes32 _requestId = requestRandomness(keyHash, fee);

        RandomRequest storage _request = _requestIdToRequest[_requestId];
        _request.tokenId = tokenId_;
        _request.user = user_;
        _request.requester = _msgSender();
    }

    function fulfillRandomness(bytes32 requestId_, uint256 randomness_) internal override {
        RandomRequest storage _request = _requestIdToRequest[requestId_];

        if (randomness_ == uint256(0)) {
            randomness_ = uint256(1);
        }

        IRandomConsumer _consumer = IRandomConsumer(_request.requester);
        _consumer.runFulfillRandomness(_request.tokenId, _request.user, randomness_);

        delete _requestIdToRequest[requestId_];
    }

    /*
     * @dev Pull out all balance of token or BNB in this contract. When tokenAddress_ is 0x0, will transfer all BNB to the admin owner.
     */
    function pullFunds(address tokenAddress_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenAddress_ == address(0)) {
            payable(_msgSender()).transfer(address(this).balance);
        } else {
            IERC20 token = IERC20(tokenAddress_);
            token.transfer(_msgSender(), token.balanceOf(address(this)));
        }
    }

}
