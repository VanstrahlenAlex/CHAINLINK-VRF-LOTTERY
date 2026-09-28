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
	uint256 constant ROUND_DURATION = 1 hours;
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
	
	function setUp() public {
		// 1. Deploy VRF Coordinator Mock 
		vrfCoordinatorMock = new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE, MOCK_WEI_PER_UNIT_LINK);

		// 2.Create & fund subscription
		subscriptionId = vrfCoordinatorMock.createSubscription();
		vrfCoordinatorMock.fundSubscription(subscriptionId, 1000 ether);


		// 3.Deploy Lottery
		vm.prank(OWNER);
		lottery = new Lottery(address(vrfCoordinatorMock),
			 KEY_HASH, 
			 subscriptionId,
			 CALLBACK_GAS_LIMIT,
			 TICKET_PRICE,
			 ROUND_DURATION,
			 MAX_TICKETS_PER_PLAYER,
			 MIN_PLAYER,
			 PROTOCOL_FEE_BPS
			 );

		// 4. Register Lottery as VRF consumer
		vrfCoordinatorMock.addConsumer(subscriptionId, address(lottery));

		// 5. Fund Players with TEST ETH
		vm.deal(PLAYER_1, 10 ether);
		vm.deal(PLAYER_2, 10 ether);
		vm.deal(PLAYER_3, 10 ether);
		vm.deal(PLAYER_4, 10 ether);
		vm.deal(PLAYER_5, 10 ether);
		vm.deal(PLAYER_6, 10 ether);
		vm.deal(PLAYER_7, 10 ether);
		vm.deal(PLAYER_8, 10 ether);
		vm.deal(PLAYER_9, 10 ether);
		vm.deal(PLAYER_10, 10 ether);
	}

	

}
