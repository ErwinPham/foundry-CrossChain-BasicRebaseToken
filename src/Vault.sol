//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    /**
     * ERROR
     */
    error Vault__TransferFailed();

    /**
     * VARIABLES
     */
    IRebaseToken private immutable i_rebaseToken;

    /**
     * EVENTS
     */
    event Deposit(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);

    constructor(IRebaseToken rebaseToken) {
        i_rebaseToken = rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice Allow users to deposit Eth and mint rebase Tokens in return
     */
    function deposit() external payable {
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allow users to redeem Eth and burn rebase Tokens in return
     * @param _amount Amount user want to redeem and burn
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__TransferFailed();
        }
        emit Redeemed(msg.sender, _amount);
    }

    function getRebaseTokenAdderss() external view returns (address) {
        return address(i_rebaseToken);
    }
}
