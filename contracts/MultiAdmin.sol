// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IBlindBox{function transferAdmin(address) external;}

interface IDefinaCard{function setAdmin(address) external;}

interface INFTMarket{function transferOwnership(address) external;}

interface INFTMaster{function transferOwnership(address) external;}

interface IFinaMaster{function transferOwnership(address) external;}

interface IFinaToken{function transferAdmin(address) external;}

/**
 * @dev Contract which allows majority of proposed admins to control the owned contracts.
 * 
 * Any admin can propose a superAdmin_, but minimum 3 admins out of 5 
 * are needed to confirm a SuperAdmin.
 * 
 * A SuperAdmin can be a wallet outside those 5 admins for access control proposes.
 * 
 * Any admin can make one vote. Mnimum 3 votes are needed to perform 
 * important transactions via modifier majority().
 * 
 * In case when 2 out of 5 admin wallets are compromised, the remaining 3 admins can propose
 * and confirm a SuperAdmin who can replace the comprosed admin wallets.
 * 
 * If 3 out of 5 admin wallets are compromised and as long as the 3 compromised wallets are not
 * controlled by the same party, the remaining 2 admins can propose the overturn() method, which
 * if not rejected by the other 3 admins at the same time (we allow for 600 seconds) within a month,
 * can appoint one admin out of the two admins as the new SuperAdmin.
 * 
 * To stop 2 compromised admin walltes from successfully overturning the SuperAdmin, all the remaining
 * admins are required to check back this contract at least twice a month to see if any overturn is proposed.
 * 
 * If 3 out of 5 admin wallets are compromised and controlled by the same party, it will be time for us to 
 * consider using another more secure blockchain.
 * 
 * @dev Remember for the SuperAdmin it is important to immediately reset votes after use.
 * This is to prevent the unlikely situation that SuperAdmin wallet may also be compromised.
 * 
 */
 
contract MultiAdmin is Pausable {
    
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    
    //contracts to be owned by this contract
    address public addrNFTMarket;
    address public addrNFTMaster;
    address public addrFinaToken;
    address public addrFinaMaster;
    address public addrDefinaCard;
    address public addrBlindBox;
    
    EnumerableSet.AddressSet private admins;
    EnumerableSet.AddressSet private proposedSuperAdmins;
    
    //there can only be one confirmed superAdmin which is processed via confirmSuperAdmin().
    address public superAdmin; 
    //counter mapping for admin votes, can only be 0 or 1.
    mapping(address => uint8) public adminVotes;
    //counter mapping for proposed superadmins and its vote by each admin, can only be 0 or 1.
    mapping(address => mapping(address => uint8)) public superAdminVotes; 
    //counter mapping for total votes for the proposed superAdmin.
    mapping(address => uint8) public totalSuperVotes;
    
    //remember to use resetVotes() after required transactions are finished.
    uint8 public totalVotes; 
    
    //counter for total overturn() Votes.
    uint8 public overturnTotalVotes;
    //counter mapping for overturn vote from each admin.
    mapping(address => uint8) public overturnAdminVote;
    //bool mapping for overturn vote from each admin. False = not proposed; True = proposed.
    mapping(address => bool) public overturnAdminPosition;
    //set for each proposed overturn timestamp from each admin (proposal start time plus one month).
    EnumerableSet.UintSet private overturnAdminEndtime;
    //set for each overturn rejection timestamp from each admin.
    EnumerableSet.UintSet private overturnRejectionTime;
    
    constructor(address[] memory admins_){
        //we use a total of 5 admins, and minimum 3 is required for proposed transactions.
        require(admins_.length == 5, "admin number must be 5"); 
        for (uint i = 0; i < admins_.length; i++){
            admins.add(admins_[i]);
            //set initial votes to 0.
            adminVotes[admins_[i]] = 0;
        }
    }
    
    modifier majority() {
        require(totalVotes >= 3, "majority votes not reached!");
        _;
    }

    modifier onlyAdmin() {
        require(admins.contains(_msgSender()), "not called by admin!");
        _;
    }
    
    modifier onlySuperAdmin() {
        require(_msgSender() == superAdmin, "not called by superAdmin!");
        _;
    }
    function inspectVotes() public view returns(uint) {
        return adminVotes[_msgSender()];
    }

    function endTimeAtIndex(uint index) public view returns(uint) {
        require(index < overturnAdminEndtime.length(), "index out of bounds!");
        return overturnAdminEndtime.at(index);
    }

    function rejectionTimeAtIndex(uint index) public view returns(uint) {
        require(index < overturnRejectionTime.length(), "index out of bounds!");
        return overturnRejectionTime.at(index);
    }
    function adminAtIndex(uint8 index) public view returns(address) {
        require(index < admins.length(), "index out of bounds!");
        return admins.at(index);
    }
    
    function isAdmin() view public returns (bool) {
        return admins.contains(_msgSender());
    }
    
    //Can be used to replace a compromised wallet
    function resetAdmin(address oldAdmin, address newAdmin) external majority onlySuperAdmin {
        require(admins.contains(oldAdmin), "oldAdmin not exists!");
        admins.remove(oldAdmin);
        admins.add(newAdmin);
        //reset votes also.
        totalVotes = 0;
        for (uint i = 0; i < admins.length(); i++){
            adminVotes[admins.at(i)] = 0;
        }
        for (uint i = 0; i < proposedSuperAdmins.length(); i++){
            totalSuperVotes[proposedSuperAdmins.at(i)] = 0;
            for (uint j = 0; j < admins.length(); j++){
                superAdminVotes[proposedSuperAdmins.at(i)][admins.at(j)] = 0;}
        }
    }

    function renounceSuperAdmin() public onlySuperAdmin {
        superAdmin = address(0);
    }

    /**
     * @dev This will also reset superAdmin for security purposes.
     * 
     */
    function resetVotes() external majority onlySuperAdmin {
        totalVotes = 0;
        for (uint i = 0; i < admins.length(); i++){
            adminVotes[admins.at(i)] = 0;
        }
        for (uint i = 0; i < proposedSuperAdmins.length(); i++){
            totalSuperVotes[proposedSuperAdmins.at(i)] = 0;
            for (uint j = 0; j < admins.length(); j++){
                superAdminVotes[proposedSuperAdmins.at(i)][admins.at(j)] = 0;}
        }
        renounceSuperAdmin();
    }
    
    function vote() external onlyAdmin {
        //double voting not allowed
        require(adminVotes[_msgSender()] == 0, "already voted!");
        adminVotes[_msgSender()] = 1;
        totalVotes += adminVotes[_msgSender()];
    }

    /**
     * @dev Use this function to propose a new superAdmin_ and vote for them. 
     */
    function voteSuperAdmin(address superAdmin_) external onlyAdmin {
        require(superAdminVotes[superAdmin_][_msgSender()] == 0, "already voted!");
        superAdminVotes[superAdmin_][_msgSender()] = 1;
        totalSuperVotes[superAdmin_] += 1;
        proposedSuperAdmins.add(superAdmin_);
    }
    
    /**
     * @dev Must be called by the proposed superAdmin_ wallet.
     * 
     * minimum 3 votes needed to confirm the superAdmin.
     */
    function confirmSuperAdmin(address superAdmin_) external {
        require(proposedSuperAdmins.contains(_msgSender()), "msg sender is not a proposed superAdmin");
        require(totalSuperVotes[superAdmin_] >= 3,"votes not reached majority");
        superAdmin = superAdmin_;
        //reset superAdmin votes so that if a new superAdmin is
        //appointed, this superAdmin is no longer in force.
        for (uint i = 0; i < proposedSuperAdmins.length(); i++){
            totalSuperVotes[proposedSuperAdmins.at(i)] = 0;
            for (uint j = 0; j < admins.length(); j++){
                superAdminVotes[proposedSuperAdmins.at(i)][admins.at(j)] = 0;}
        }
    }

    /**
     * @dev Must be called by two admins to propose an overturn.
     * Wait for a month before an overturn can be effective.
     */
    function overturnVote() external onlyAdmin {
        require(overturnAdminVote[_msgSender()] == 0, "already voted by msg sender!");
        require(overturnAdminPosition[_msgSender()] == false, "already proposed by msg sender!");
        require(overturnAdminEndtime.length() <=2, "max 2 admins can propose overturn!");
        overturnAdminVote[_msgSender()] = 1;
        overturnTotalVotes += overturnAdminVote[_msgSender()];
        overturnAdminEndtime.add(block.timestamp + 30 days);//after one month.
        overturnAdminPosition[_msgSender()] = true;
    }
    
    /**
     * @dev Must be called by one of the two admins who proposed an overturn.
     * However it is possible to reject the overturn when 3 other admins vote 
     * for rejection at nearly the same time (within 600 seconds).
     */
    function overturn() external onlyAdmin {
        require(overturnAdminEndtime.length() == 2, "2 admins must have proposed overturn!");
        require(block.timestamp >= overturnAdminEndtime.at(1), "can only be called after one month of initial proposal!");
        require(overturnAdminVote[_msgSender()] == 1, "can only be called by an overturn proposer!");
        require(overturnTotalVotes == 2, "2 admins votes are needed for this proposal");
        //three rejections must be done within one minute to void the overturn proposal.
        if(overturnRejectionTime.length() == 3){
            uint maxRejectionTime; uint minRejectionTime;
            for (uint i = 1; i < 3; i++){
                maxRejectionTime = overturnRejectionTime.at(i) > overturnRejectionTime.at(i-1) ? overturnRejectionTime.at(i) : overturnRejectionTime.at(i-1);
                minRejectionTime = overturnRejectionTime.at(i) < overturnRejectionTime.at(i-1) ? overturnRejectionTime.at(i) : overturnRejectionTime.at(i-1);
            }
            if(maxRejectionTime <= minRejectionTime + 600){
                //if rejection success, reset counters.
                resetOverturn();
            } else {
                //else just reset rejection counters
                for (uint i = 0; i < overturnRejectionTime.length(); i++){
                    overturnRejectionTime.remove(overturnRejectionTime.at(i));
                }
                for (uint i = 0; i < admins.length(); i++){
                    overturnAdminPosition[admins.at(i)] = false;
                }
            }
        }
        else {
            //if overturn success, set superAdmin and reset counters.
            superAdmin = _msgSender();
            resetOverturn();
        }
    }
    
    //reset overturn counters whether successful or not.
    function resetOverturn() internal {
        overturnTotalVotes = 0;
        for (uint i = 0; i < admins.length(); i++){
            overturnAdminVote[admins.at(i)] = 0;
            overturnAdminPosition[admins.at(i)] = false;
        }
        overturnAdminEndtime.remove(overturnAdminEndtime.at(0));
        overturnAdminEndtime.remove(overturnAdminEndtime.at(0));
        for (uint i = 0; i < overturnRejectionTime.length(); i++){
            overturnRejectionTime.remove(overturnRejectionTime.at(i));
        }
    }
    
    /**
     * @dev In case two compromised wallets propose an overturn, it is advised
     * for the remaining admins to keep regular checks on this contract, and Use
     * superAdmin to replace compromised wallets so they cannot propose overturn again.
     */    
    function rejectOverturn() external onlyAdmin{
        require(overturnAdminPosition[_msgSender()] == false, "already proposed by msg sender!");
        //get last recorded end time from overturn proposal
        uint lastRecordedEndTime = overturnAdminEndtime.at(1) > overturnAdminEndtime.at(0) ? overturnAdminEndtime.at(1) : overturnAdminEndtime.at(0);
        require(lastRecordedEndTime > 0, "lastRecordedEndTime cannot be zero!");
        require(block.timestamp <= lastRecordedEndTime, "one month has passed!");
        require(overturnRejectionTime.length() <=3, "max 3 admins can propose rejection of overturn!");
        overturnRejectionTime.add(block.timestamp);
        overturnAdminPosition[_msgSender()] = true;
    }
    
    function updateNFTMarket(address _new) external majority onlySuperAdmin whenPaused {
        addrNFTMarket = _new;
    }
    
    function updateNFTMaster(address _new) external majority onlySuperAdmin whenPaused {
        addrNFTMaster = _new;
    }

    function updateFinaToken(address _new) external majority onlySuperAdmin whenPaused {
        addrFinaToken = _new;
    }

    function updateFinaMaster(address _new) external majority onlySuperAdmin whenPaused {
        addrFinaMaster = _new;
    }

    function updateDefinaCard(address _new) external majority onlySuperAdmin whenPaused {
        addrDefinaCard = _new;
    }

    function updateBlindbox(address _new) external majority onlySuperAdmin whenPaused {
        addrBlindBox = _new;
    }

    //minimum 3 votes needed to pause
    function pause() external majority onlyAdmin whenNotPaused() {
        _pause();
    }

    function unpause() external majority onlyAdmin whenPaused {
        _unpause();
    }

    function changeAdminOfBlindBox(address newOwner) external majority onlySuperAdmin whenPaused {
        IBlindBox(addrBlindBox).transferAdmin(newOwner);
    }

    function changeAdminOfDefinaCard(address newOwner) external majority onlySuperAdmin whenPaused {
        IDefinaCard(addrDefinaCard).setAdmin(newOwner);
    }
    
    function changeOwnerOfNFTMarket(address newOwner) external majority onlySuperAdmin whenPaused {
        INFTMarket(addrNFTMarket).transferOwnership(newOwner);
    }

    function changeOwnerOfNFTMaster(address newOwner) external majority onlySuperAdmin whenPaused {
        INFTMaster(addrNFTMaster).transferOwnership(newOwner);
    }

    function changeOwnerOfFinaMaster(address newOwner) external majority onlySuperAdmin whenPaused {
        IFinaMaster(addrFinaMaster).transferOwnership(newOwner);
    }

    function changeOwnerOfFinaToken(address newOwner) external majority onlySuperAdmin whenPaused {
        IFinaToken(addrFinaToken).transferAdmin(newOwner);
    }
    
    /*
     * @dev Pull out all balance of token or BNB in this contract. When tokenAddress_ is 0x0, will transfer all BNB to the admin owner.
     */
    function pullFunds(address tokenAddress_) external majority onlySuperAdmin {
        if (tokenAddress_ == address(0)) {
            payable(_msgSender()).transfer(address(this).balance);
        } else {
            IERC20 token = IERC20(tokenAddress_);
            token.transfer(_msgSender(), token.balanceOf(address(this)));
        }
    }

}