//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Satori Rebase Token
 * @author Huy Pham (Satori)
 * @notice This is a cross-chain rebase token that incentivises user to deposit
 * into a vault and gain interest in rewwards.
 * @notice The interest rate in smart contract just can only decrease
 * @notice Each user will have their own interest rate that is the global interest
 * rate at the time of depositing
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    /**
     * ERROR
     */
    error RebaseToken__InterestRateJustOnlyDecrease(uint256 oldRate, uint256 newRate);

    /**
     * VARIABLES
     */
    uint256 private s_interestRate = (5 * PRECISION) / 1e8; //0,000000005
    mapping(address user => uint256 rate) private s_userToInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;
    uint256 public constant PRECISION = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    /**
     * EVENTS
     */
    event InterestRateSet(uint256 indexed interestRate);

    constructor() Ownable(msg.sender) ERC20("Satori Rebase Token", "MyCent") {}

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                             PUBLIC AND EXTERNAL FUNCTIONS                                //
    //////////////////////////////////////////////////////////////////////////////////////////////

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice This function set the interest rate
     * @param _newInterestrate The new interest rate
     * @dev The interest rate just only decrease
     */
    function setInterestRate(uint256 _newInterestrate) external onlyOwner {
        if (_newInterestrate >= s_interestRate) {
            revert RebaseToken__InterestRateJustOnlyDecrease(s_interestRate, _newInterestrate);
        }
        s_interestRate = _newInterestrate;
        emit InterestRateSet(_newInterestrate);
    }

    /**
     * @notice Mint the user token when they deposit into vault
     * @param _to The user to mint tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userToInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn token from user who withdraw money from the vault
     * @param _from The user to burn tokens
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Get principle balance of a user. This is the number of tokens that have currently been minted to the user,
     * not including any interest that has accrued since the last time the user interacted with the protocol
     * @param user The user to get principle balance
     * @return The principle balance of user
     */
    function principleBalanceOf(address user) external view returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @notice This function calculates the balance of user including the interest that has accumulated
     * since the last update. (principle balance) * some interest that has accrued
     * @param user The user to calculate the balance
     */
    function balanceOf(address user) public view override returns (uint256) {
        return (super.balanceOf(user) * _calculatingAccumulatedInterestScinceLastUpdate(user)) / PRECISION;
    }

    /**
     * @notice Transfer token from user to another
     * @param _to Transfer to
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transfer(address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_to) == 0) {
            s_userToInterestRate[_to] = s_userToInterestRate[msg.sender];
        }
        return super.transfer(_to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }

        if (balanceOf(_to) == 0) {
            s_userToInterestRate[_to] = s_userToInterestRate[_from];
        }
        return super.transferFrom(_from, _to, _amount);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                             PRIVATE AND INTERNAL FUNCTIONS                               //
    //////////////////////////////////////////////////////////////////////////////////////////////

    function _mintAccruedInterest(address user) internal {
        uint256 previousPrincipleBalance = super.balanceOf(user);
        uint256 currentUserBalance = balanceOf(user);
        uint256 balanceIncrease = currentUserBalance - previousPrincipleBalance;
        s_userLastUpdatedTimestamp[user] = block.timestamp;
        _mint(user, balanceIncrease);
    }

    /**
     * @notice This function calculates the interest that has accumulated since the last update
     * @param user The user to calculate the interest
     */
    function _calculatingAccumulatedInterestScinceLastUpdate(address user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[user];
        linearInterest = PRECISION + (s_userToInterestRate[user] * timeElapsed);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                                   GETTER FUNCTIONS                                       //
    //////////////////////////////////////////////////////////////////////////////////////////////

    function getUserInterestRate(address user) external view returns (uint256) {
        return s_userToInterestRate[user];
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getUserLastTimeUpdateTimestamp(address user) external view returns (uint256) {
        return s_userLastUpdatedTimestamp[user];
    }
}
