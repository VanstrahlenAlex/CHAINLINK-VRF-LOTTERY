// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @title Lottery
/// @author Alexander Van strahlen
/// @notice A multi-round lottery system using Chainlink VRF V2.5 for provable fair winner selection. 
// Each round has a configurable time window, ticket price, and max tickets per player. 
// Three winner are selected per round with a 50/30/20 prize split 



contract Lottery is VRFConsumerBaseV2Plus {
	
	enum RoundState {
		OPEN,
		CALCULATING, 
		CLOSED
	}

	struct LotteryConfig {
		uint256 ticketPrice;
		uint256 roundDuration;
		uint256 maxTicketsPerPlayer;
		uint256 minPlayers;
		uint256 protocolFeeBps; //Basis points, max 1000 (10%) 
	}

	struct Round {
		RoundState state;
		uint256 startTime;
		uint256 endTime;
		uint256 ticketPrice;
		uint256 maxticketsPerPlayer;
		uint256 minPlayers;
		uint16 protocolFeeBps;
		uint256 prizePool;
		uint256 protocolFeeCollected; 
		address[] players;
		address[] uniquePlayers;
		address[3] winners;
		uint256[3] payouts;
		uint256 vrfRequestId;
		bool refunded;
	}

	// _________________________________________________
	// Errors
	// _________________________________________________

	error Lottery__RoundNotOpen(uint256 roundId);
	error Lottery__RoundNotCalculating(uint256 roundId);
	error Lottery__RoundStillOpen(uint256 roundId);
	error Lottery__InsufficientPayment(uint256 sent, uint256 required);
	error Lottery__MaxTicketsExceeded(uint256 requested, uint256 max);
	error Lottery__ZeroTickets();
	error Lottery__TransferFailed(address recipient, uint256 amount);
	error Lottery__NotEnoughPlayers(uint256 current, uint256 required);
	error Lottery__InvalidTicketPrice();
	error Lottery__InvalidRoundDuration();
	error Lottery__InvalidMaxTickets();
	error Lottery__InvalidProtocolFee();
	error Lottery__InvalidMinPlayers();
	error Lottery__NoRefundAvailable();
	error Lottery__NothingToWithdraw();
	error Lottery__PreviousRoundNotClosed();

	// _________________________________________________
	// Events
	// _________________________________________________

	event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime, uint256 ticketPrice);
	event TicketsPurchased(uint256 indexed roundId, address indexed player, uint256 quantity, uint256 totalPlayerTickets);
	event DrawRequested(uint256 indexed roundId, uint256 indexed vrfRequestId);
	event WinnersSelected(uint256 indexed roundId, address[3] winners, uint256[3] payouts);
	event RoundRefunded(uint256 indexed roundId, uint256 playerCount);
	event RefundClaimed(uint256 indexed roundId, address indexed player, uint256 amount);
	event ProtocolFeeCollected(uint256 indexed roundId, uint256 amount);
	event FeesWithdrawn(address indexed to, uint256 amount);
	event ConfigUpdated(uint256 ticketPrice, uint256 roundDuration, uint256 maxTicketsPerPlayer, uint256 minPlayers, uint16 protocolFeeBps);

	uint16 private constant MAX_PROTOCOL_FEE_BPS = 1000; // 10% 
	uint16 private constant REQUEST_CONFIRMATIONS = 3;
	uint32 private constant NUM_WORD = 3;
	uint16 private constant FIRST_PLACE_BPS = 50_00; // 50;
	uint16 private constant SECOND_PLACE_BPS = 30_00; // 30; 

	//VRF VARIABLES 
	bytes32 private immutable i_keyHash;
	uint256 private immutable i_subscriptionId;
	uint32 private immutable i_callbackGasLimit;
	
	LotteryConfig private s_config;
	uint256 private s_currentRoundId;
	uint256 private s_accumulatedFees;

	mapping(uint256 roundId => Round) private s_rounds;
	mapping(uint256 vrfRequestId => uint256 roundId) private s_vrfRequestToRound;
	mapping(uint256 roundId => mapping(address player => uint256 tickets)) private s_playerTickets;   



	constructor(address vrfCoordinator) VRFConsumerBaseV2Plus(vrfCoordinator) {
    // resto de tu inicialización (ticketPrice, roundDuration, etc.) si aplica
	}

	function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
		// TODO: usar randomWords para elegir a los 3 ganadores de la ronda
		// asociada a este requestId, calcular payouts (50/30/20) y actualizar
		// el estado del Round correspondiente.
	}

}