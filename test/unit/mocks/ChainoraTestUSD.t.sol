// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ChainoraTestUSD} from "src/mocks/ChainoraTestUSD.sol";

contract ChainoraTestUSDTest is Test {
    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;

    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    address internal burner = address(0xCAFE);

    ChainoraTestUSD internal token;

    function setUp() public {
        token = new ChainoraTestUSD(owner, INITIAL_SUPPLY);
    }

    function testConstructorSetsMetadataOwnerAndSupply() public view {
        assertEq(token.name(), "Test Chainora USD");
        assertEq(token.symbol(), "tcUSD");
        assertEq(token.decimals(), 18);
        assertEq(token.owner(), owner);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    function testOwnerCanMint() public {
        vm.prank(owner);
        token.mint(user, 100 ether);

        assertEq(token.balanceOf(user), 100 ether);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + 100 ether);
    }

    function testNonOwnerCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));

        vm.prank(user);
        token.mint(user, 1 ether);
    }

    function testHolderCanBurn() public {
        vm.prank(owner);
        assertTrue(token.transfer(user, 50 ether));

        vm.prank(user);
        token.burn(10 ether);

        assertEq(token.balanceOf(user), 40 ether);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - 10 ether);
    }

    function testApprovedBurnerCanBurnFrom() public {
        vm.prank(owner);
        assertTrue(token.transfer(user, 50 ether));

        vm.prank(user);
        assertTrue(token.approve(burner, 25 ether));

        vm.prank(burner);
        token.burnFrom(user, 20 ether);

        assertEq(token.balanceOf(user), 30 ether);
        assertEq(token.allowance(user, burner), 5 ether);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - 20 ether);
    }
}
