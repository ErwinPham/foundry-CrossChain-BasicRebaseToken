//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    /**
     * errors
     */
    error TransferFailed();

    RebaseToken private rebaseToken;
    Vault private vault;

    address public user = makeAddr("user");
    address public owner = makeAddr("onwer");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        IRebaseToken(address(rebaseToken)).grantMintAndBurnRole(address(vault));
        //(bool success,) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("start Balance: ", startBalance);
        assertEq(startBalance, amount);

        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(amount, rebaseToken.balanceOf(user));

        vault.redeem(amount);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function _addRewardToVault(uint256 amount) internal {
        (bool sucess,) = payable(address(vault)).call{value: amount}("");
        if (!sucess) {
            revert TransferFailed();
        }
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        time = bound(time, 1000, type(uint96).max);

        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        vm.warp(block.timestamp + time);
        uint256 balance = rebaseToken.balanceOf(user);

        uint256 interest = balance - depositAmount;

        vm.deal(owner, interest);
        vm.prank(owner);
        _addRewardToVault(interest);

        vm.startPrank(user);
        vault.redeem(type(uint256).max);
        assertEq(address(user).balance, balance);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertGt(balance, depositAmount);
        vm.stopPrank();
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(user2Balance, 0);
        assertEq(userBalance, amount);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTrans = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTrans = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTrans, amount - amountToSend);
        assertEq(user2BalanceAfterTrans, user2Balance + amountToSend);
        assertEq(rebaseToken.getUserInterestRate(user2), rebaseToken.getUserInterestRate(user));

        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterOneDay = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterOneDay = rebaseToken.balanceOf(user2);

        assertGt(userBalanceAfterOneDay, userBalanceAfterTrans);
        assertGt(user2BalanceAfterOneDay, user2BalanceAfterTrans);
    }

    function testCannotSetInterestRateByUser(uint256 newInterestRate) public {
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    function testCannotCallMintAndBurnByUser() public {
        uint256 rate = rebaseToken.getInterestRate();
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.mint(user, 100, rate);
        vm.expectRevert();
        rebaseToken.burn(user, 100);
        vm.stopPrank();
    }

    function testCanGetPrincipleBalance(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        vm.warp(block.timestamp + 1 days);

        uint256 principleBalance = rebaseToken.principleBalanceOf(user);
        assertEq(principleBalance, amount);
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
