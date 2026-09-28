// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test, console2} from "forge-std/Test.sol";
import {Lottery} from "../src/Lottery.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";


contract LotteryTest is Test {
	
	Lottery public lottery;
	VRFCoordinatorV2_5Mock public vrfCoordinatorMock;
	
	// VRF Mock Config
	uint96 constant MOCK_BASE_FEE = 0.25 ether;
	uint96 constant MOCK_GAS_PRICE = 1e9;
	int256 constant MOCK_WEI_PER_UNIT_LINK = 4e15;

	//Lottery Config
	bytes32 constant KEY_HASH = bytes32(uint256(1));
	uint32 constant CALLBACK_GAS_LIMIT = 500_000;
	uint256 constant TICKET_PRICE = 0.01 ether;
	uint256 constant ROUND_DURATIO = 1 hours;
	uint256 constant MAX_TICKETS_PER_PLAYER = 10;
	uint256 constant MIN_PLAYER = 3;
	uint16 constant PROTOCOL_FEE_BPS = 500;

	address OWNER = makeAddr("owner");
	address PLAYER_1 = makeAddr("player1");
	address PLAYER_2 = makeAddr("player2");
	address PLAYER_3 = makeAddr("player3");
	address PLAYER_4 = makeAddr("player4");
	address PLAYER_5 = makeAddr("player5");
	address PLAYER_6 = makeAddr("player6");
	address PLAYER_7 = makeAddr("player7");
	address PLAYER_8 = makeAddr("player8");
	address PLAYER_9 = makeAddr("player9");
	address PLAYER_10 = makeAddr("player10");


	uint256 subscriptionId; 
	

}
