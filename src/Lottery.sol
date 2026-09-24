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
		uint256 maxTicketsPerPlayer;
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
	uint32 private constant NUM_WORDS = 3;
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
	// External - CORE
	//_____________________________________________________

	function startNewRound() external onlyOwner() {
		if(s_currentRoundId > 0){
			Round storage prev = s_rounds[s_currentRoundId];
			if(prev.state != RoundState.CLOSED) revert Lottery__PreviousRoundNotClosed();			
		}

		s_currentRoundId++;
		uint256 roundId = s_currentRoundId;
		LotteryConfig memory cfg = s_config;

		Round storage r = s_rounds[roundId];
		r.state = RoundState.OPEN;
		r.startTime = block.timestamp;
		r.endTime = block.timestamp + cfg.roundDuration;
		r.ticketPrice = cfg.ticketPrice;
		r.maxTicketsPerPlayer = cfg.maxTicketsPerPlayer;
		r.minPlayers = cfg.minPlayers;
		r.protocolFeeBps = cfg.protocolFeeBps;

		emit RoundStarted(roundId, r.startTime, r.endTime, r.ticketPrice);
	}

	function buyTickets(uint256 quantity) external payable {
		if(quantity == 0) revert Lottery__ZeroTickets();
		
		uint256 roundId = s_currentRoundId;
		Round storage r = s_rounds[roundId];

		if(r.state != RoundState.OPEN) revert Lottery__RoundNotOpen(roundId);
		if(block.timestamp >= r.endTime) revert Lottery__RoundNotOpen(roundId);

		uint256 totalCost = r.ticketPrice * quantity;
		if(msg.value < totalCost) revert Lottery__InsufficientPayment(msg.value, totalCost);

		uint256 currentTickets = s_playerTickets[roundId][msg.sender];
		if(currentTickets + quantity > r.maxTicketsPerPlayer) revert Lottery__MaxTicketsExceeded(currentTickets + quantity, r.maxTicketsPerPlayer);
		
		if(currentTickets == 0){
			r.uniquePlayers.push(msg.sender);

		}

		s_playerTickets[roundId][msg.sender] = currentTickets + quantity;
		
		for(uint256 i; i < quantity; i++){
			r.players.push(msg.sender);
		}
		
		r.prizePool += totalCost;
		
		emit TicketsPurchased(roundId, msg.sender, quantity, currentTickets + quantity);

		uint256 excess = msg.value - totalCost;
		if (excess > 0) {
			(bool ok, ) = msg.sender.call{value: excess}("");
			require(ok, "Transfer Failed. Please request a refund.");			
		}
	}

	/// @notice Claim a refund for a cancelled round (not enough players)
	/// @param roundId The refunded round
	function claimRefund(uint256 roundId) external {
		Round storage r = s_rounds[roundId];
		
		if(!r.refunded) revert Lottery__NoRefundAvailable();

		uint256 tickets = s_playerTickets[roundId][msg.sender];
		if (tickets == 0) revert Lottery__NoRefundAvailable();

		uint256 refundAmount = tickets * r.ticketPrice;

		s_playerTickets[roundId][msg.sender] = 0;

		(bool ok, ) = msg.sender.call{value: refundAmount}("");
		require(ok, "Transfer failed");

		emit RefundClaimed(roundId, msg.sender, refundAmount);
	}

	function requestDraw(uint256 roundId) external {
		Round storage r = s_rounds[roundId];

		if (r.state != RoundState.OPEN) revert Lottery__RoundNotOpen(roundId);
		if (block.timestamp < r.endTime) revert Lottery__RoundNotOpen(roundId);
		
		if(r.uniquePlayers.length < r.minPlayers) {
			r.state = RoundState.CLOSED;
			r.refunded = true; 
			emit RoundRefunded(roundId, r.uniquePlayers.length);
			return;
		}
		r.state = RoundState.CALCULATING;

		uint256 requestId = s_vrfCoordinator.requestRandomWords(
			
			VRFV2PlusClient.RandomWordsRequest({
				keyHash: i_keyHash, 
				subId : i_subscriptionId, 
				requestConfirmations: REQUEST_CONFIRMATIONS,
				callbackGasLimit: i_callbackGasLimit, 
				numWords: NUM_WORDS,
				extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
			})
		);

		r.vrfRequestId = requestId;
		s_vrfRequestToRound[requestId] = roundId;

		emit DrawRequested(roundId, requestId);
		
	}

	function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
		uint256 roundId = s_vrfRequestToRound[requestId];
		Round storage r = s_rounds[roundId];

		uint256 totalPool = r.prizePool; 
		uint256 protocolFee = (totalPool * r.protocolFeeBps) / 10_000;
		uint256 distributablePool = totalPool - protocolFee;

		s_accumulatedFees += protocolFee;
		r.protocolFeeCollected = protocolFee; 

		uint256 numUniquePlayers = r.uniquePlayers.length;
		uint256 numWinners = numUniquePlayers < 3 ? numUniquePlayers : 3;

		address[] memory selected = _selectUniqueWinners(r.players, randomWords, numWinners);

		uint256[3] memory payouts; 

		if(numWinners = 1) {
			payouts[0] = distributablePool;
		} else if (numWinners == 2) {
			payouts[0] = (distributablePool * 6000) / 10_000; // 60%
			payouts[1] = distributablePool - payouts[0]; // 40%
		} else {
			payouts[0] = (distributablePool * FIRST_PLACE_BPS) / 10_000; // 50%
			payouts[1] = (distributablePool * SECOND_PLACE_BPS) / 10_000; // 30%
			payouts[2] = distributablePool - payouts[0] - payouts[1]; // 20% (remainder avoids dust)
		}

		for(uint256 i; i < numWinners; i++) {
			r.winners[i] = selected[i];
		}
		r.payouts = payouts;
		r.state = RoundState.CLOSED;

		emit ProtocolFeeCollected(roundId, protocolFee);
		
	}



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

	function withdrawFees(address to) external onlyOwner {
		uint256 amount = s_accumulatedFees;
		if (amount == 0) revert Lottery__NothingToWithdraw();
		
		s_accumulatedFees = 0;
		(bool ok, ) = to.call{value: amount}("");
		require(ok, "Transfer Failed. Please withdraw manually.");

		emit FeesWithdrawn(to, amount);

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