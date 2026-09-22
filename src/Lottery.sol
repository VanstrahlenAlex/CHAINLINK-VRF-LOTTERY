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
		uint16 protocolFeeBps; //Basis points, max 1000 (10%) 
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



	/// @param vrfCoordinator Chainlink VRF V2.5 Coordinator address
	/// @param keyHash VRF KeyHash for the network 
	/// @param subscriptionId VRF Subscription ID for funding LINK
	/// @param callbackGasLimit Gas limit for VRF callback
	/// @param ticketPrice Initial ticket price
	/// @param roundDuration Initial round duration in seconds
	/// @param maxTicketsPerPlayer Initial maximum number of tickets per player
	/// @param minPlayers Initial minimum number of players required
	/// @param protocolFeeBps Initial protocol fee in basis points (max 1000 for 10%)

	constructor(
		address vrfCoordinator,
		bytes32 keyHash,
		uint256 subscriptionId,
		uint32 callbackGasLimit,
		uint256 ticketPrice,
		uint256 roundDuration,
		uint256 maxTicketsPerPlayer,
		uint256 minPlayers,
		uint16 protocolFeeBps
		) VRFConsumerBaseV2Plus(vrfCoordinator) {
			if(ticketPrice == 0) revert Lottery__InvalidTicketPrice();
			if(roundDuration == 0) revert Lottery__InvalidRoundDuration();
			if(maxTicketsPerPlayer == 0) revert Lottery__InvalidMaxTickets();
			if(minPlayers == 0) revert Lottery__InvalidMinPlayers();
			if(protocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert Lottery__InvalidProtocolFee();
			
			i_keyHash = keyHash;
			i_subscriptionId = subscriptionId;
			i_callbackGasLimit = callbackGasLimit;

			s_config = LotteryConfig(
				ticketPrice,
				roundDuration,
				maxTicketsPerPlayer,
				minPlayers,
				protocolFeeBps
			);
			s_currentRoundId = 1;

	}
	//_____________________________________________________
	// External - Owner Admin
	//_____________________________________________________




	//_____________________________________________________
	// External - Owner Admin
	//_____________________________________________________

	/// @notice Update ticket price for future rounds
	function setTicketPrice(uint256 newPrice) external onlyOwner {
		if(newPrice == 0) revert Lottery__InvalidTicketPrice();
		s_config.ticketPrice = newPrice;
		_emitConfigUpdated();
	}

	/// @notice Update ticket price for future rounds
	function setRoundDuration(uint256 newDuration) external onlyOwner {
		if (newDuration == 0) revert Lottery__InvalidRoundDuration();
		s_config.roundDuration = newDuration;
		_emitConfigUpdated();
	}

	/// @notice Update ticket price for future rounds
	function setMaxTicketsPerPlayer(uint256 newMaxTickets) external onlyOwner {
		if (newMaxTickets == 0) revert Lottery__InvalidMaxTickets();
		s_config.maxTicketsPerPlayer = newMaxTickets;
		_emitConfigUpdated();
	}

	/// @notice Update ticket price for future rounds
	function setMinPlayers(uint256 newMinPlayers) external onlyOwner {
		if (newMinPlayers == 0) revert Lottery__InvalidMinPlayers();
		s_config.minPlayers = newMinPlayers;
		_emitConfigUpdated();
	}

	/// @notice Update ticket price for future rounds
	function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyOwner {
		if (newProtocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert Lottery__InvalidProtocolFee();
		s_config.protocolFeeBps = newProtocolFeeBps;
		_emitConfigUpdated();
	}

	//_____________________________________________________
	// External - View 
	//_____________________________________________________

	function getRound(uint256 roundId) external view returns(Round memory) {
		return s_rounds[roundId];
	}

	function getCurrentRoundId() external view returns (uint256) {
		return s_currentRoundId;
	}

	function getConfig() external view returns (LotteryConfig memory) {
		return s_config;
	}

	function getAccumulatedFees() external view returns (uint256) {
		return s_accumulatedFees;
	}

	function getPlayerTickets(uint256 roundId, address player) external view returns (uint256) {
		return s_playerTickets[roundId][player];
	}

	function getRoundPlayers(uint256 roundId) external view returns (address[] memory) {
		return s_rounds[roundId].players;
	}

	function getRoundUniquePlayers(uint256 roundId) external view returns (address[] memory) {
		return s_rounds[roundId].uniquePlayers;
	}

	function getRoundWinners(uint256 roundId) external view returns (address[3] memory){
		return s_rounds[roundId].winners;
	}

	function getRoundPayouts(uint256 roundId) external view returns (uint256[3] memory){
		return s_rounds[roundId].payouts;
	}


	function _emitConfigUpdated() private {
		LotteryConfig memory cfg = s_config; 
		emit ConfigUpdated(cfg.ticketPrice, cfg.roundDuration, cfg.maxTicketsPerPlayer, cfg.minPlayers, cfg.protocolFeeBps);
	}

}