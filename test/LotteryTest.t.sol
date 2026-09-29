// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test, console2} from "forge-std/Test.sol";
import {Lottery} from "../src/Lottery.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

/// @dev Participant that cannot receive ETH (no receive/fallback). Used to test failing transfers.
contract RejectEther {
	function buy(Lottery lottery, uint256 quantity) external payable {
		lottery.buyTickets{value: msg.value}(quantity);
	}
}

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

	// ____________________________________________________________
	// Events (redeclared for vm.expectEmit)
	// ____________________________________________________________

	event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime, uint256 ticketPrice);
	event TicketsPurchased(uint256 indexed roundId, address indexed player, uint256 quantity, uint256 totalPlayerTickets);
	event DrawRequested(uint256 indexed roundId, uint256 indexed vrfRequestId);
	event WinnersSelected(uint256 indexed roundId, address[3] winners, uint256[3] payouts);
	event RoundRefunded(uint256 indexed roundId, uint256 playerCount);
	event RefundClaimed(uint256 indexed roundId, address indexed player, uint256 amount);
	event ProtocolFeeCollected(uint256 indexed roundId, uint256 amount);
	event FeesWithdrawn(address indexed to, uint256 amount);
	event ConfigUpdated(uint256 ticketPrice, uint256 roundDuration, uint256 maxTicketsPerPlayer, uint256 minPlayers, uint16 protocolFeeBps);

	// ____________________________________________________________
	// Helpers
	// ____________________________________________________________

	function _players() internal view returns (address[5] memory p) {
		p = [PLAYER_1, PLAYER_2, PLAYER_3, PLAYER_4, PLAYER_5];
	}

	function _startRound() internal returns (uint256 roundId) {
		vm.prank(OWNER);
		lottery.startNewRound();
		roundId = lottery.getCurrentRoundId();
	}

	function _buy(address player, uint256 qty) internal {
		vm.prank(player);
		lottery.buyTickets{value: TICKET_PRICE * qty}(qty);
	}

	/// @dev Starts a round and makes the first `n` players (max 5) buy one ticket each
	function _startRoundWithPlayers(uint256 n) internal returns (uint256 roundId) {
		roundId = _startRound();
		address[5] memory p = _players();
		for (uint256 i; i < n; i++) {
			_buy(p[i], 1);
		}
	}

	function _endRound() internal {
		vm.warp(block.timestamp + ROUND_DURATION);
	}

	function _requestDraw(uint256 roundId) internal returns (uint256 requestId) {
		_endRound();
		lottery.requestDraw(roundId);
		requestId = lottery.getRound(roundId).vrfRequestId;
	}

	/// @dev Full cycle: 5 players, draw requested, VRF fulfilled with the mock's default words
	function _completeRound() internal returns (uint256 roundId) {
		roundId = _startRoundWithPlayers(5);
		uint256 requestId = _requestDraw(roundId);
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));
	}

	// ____________________________________________________________
	// Constructor / setUp
	// ____________________________________________________________

	function test_constructor_setsConfigAndOwner() public view {
		Lottery.LotteryConfig memory cfg = lottery.getConfig();
		assertEq(cfg.ticketPrice, TICKET_PRICE);
		assertEq(cfg.roundDuration, ROUND_DURATION);
		assertEq(cfg.maxTicketsPerPlayer, MAX_TICKETS_PER_PLAYER);
		assertEq(cfg.minPlayers, MIN_PLAYER);
		assertEq(cfg.protocolFeeBps, PROTOCOL_FEE_BPS);
		assertEq(lottery.owner(), OWNER);
		assertEq(lottery.getCurrentRoundId(), 0);
		assertEq(lottery.getAccumulatedFees(), 0);
	}

	function test_constructor_revertsOnInvalidParams() public {
		address c = address(vrfCoordinatorMock);

		vm.expectRevert(Lottery.Lottery__InvalidTicketPrice.selector);
		new Lottery(c, KEY_HASH, subscriptionId, CALLBACK_GAS_LIMIT, 0, ROUND_DURATION, MAX_TICKETS_PER_PLAYER, MIN_PLAYER, PROTOCOL_FEE_BPS);

		vm.expectRevert(Lottery.Lottery__InvalidRoundDuration.selector);
		new Lottery(c, KEY_HASH, subscriptionId, CALLBACK_GAS_LIMIT, TICKET_PRICE, 0, MAX_TICKETS_PER_PLAYER, MIN_PLAYER, PROTOCOL_FEE_BPS);

		vm.expectRevert(Lottery.Lottery__InvalidMaxTickets.selector);
		new Lottery(c, KEY_HASH, subscriptionId, CALLBACK_GAS_LIMIT, TICKET_PRICE, ROUND_DURATION, 0, MIN_PLAYER, PROTOCOL_FEE_BPS);

		vm.expectRevert(Lottery.Lottery__InvalidMinPlayers.selector);
		new Lottery(c, KEY_HASH, subscriptionId, CALLBACK_GAS_LIMIT, TICKET_PRICE, ROUND_DURATION, MAX_TICKETS_PER_PLAYER, 0, PROTOCOL_FEE_BPS);

		vm.expectRevert(Lottery.Lottery__InvalidProtocolFee.selector);
		new Lottery(c, KEY_HASH, subscriptionId, CALLBACK_GAS_LIMIT, TICKET_PRICE, ROUND_DURATION, MAX_TICKETS_PER_PLAYER, MIN_PLAYER, 1001);
	}

	// ____________________________________________________________
	// startNewRound
	// ____________________________________________________________

	function test_startNewRound_opensFirstRound() public {
		vm.expectEmit(true, false, false, true);
		emit RoundStarted(1, block.timestamp, block.timestamp + ROUND_DURATION, TICKET_PRICE);

		uint256 roundId = _startRound();

		assertEq(roundId, 1);
		Lottery.Round memory r = lottery.getRound(1);
		assertEq(uint8(r.state), uint8(Lottery.RoundState.OPEN));
		assertEq(r.startTime, block.timestamp);
		assertEq(r.endTime, block.timestamp + ROUND_DURATION);
		assertEq(r.ticketPrice, TICKET_PRICE);
		assertEq(r.maxTicketsPerPlayer, MAX_TICKETS_PER_PLAYER);
		assertEq(r.minPlayers, MIN_PLAYER);
		assertEq(r.protocolFeeBps, PROTOCOL_FEE_BPS);
	}

	function test_startNewRound_onlyOwner() public {
		vm.prank(PLAYER_1);
		vm.expectRevert("Only callable by owner");
		lottery.startNewRound();
	}

	function test_startNewRound_revertsIfPreviousRoundNotClosed() public {
		_startRound();
		vm.prank(OWNER);
		vm.expectRevert(Lottery.Lottery__PreviousRoundNotClosed.selector);
		lottery.startNewRound();
	}

	function test_startNewRound_revertsWhileCalculating() public {
		uint256 roundId = _startRoundWithPlayers(5);
		_requestDraw(roundId);

		vm.prank(OWNER);
		vm.expectRevert(Lottery.Lottery__PreviousRoundNotClosed.selector);
		lottery.startNewRound();
	}

	function test_startNewRound_secondRoundUsesUpdatedConfig() public {
		_completeRound();

		vm.startPrank(OWNER);
		lottery.setTicketPrice(0.02 ether);
		lottery.setRoundDuration(2 hours);
		lottery.startNewRound();
		vm.stopPrank();

		Lottery.Round memory r = lottery.getRound(2);
		assertEq(lottery.getCurrentRoundId(), 2);
		assertEq(r.ticketPrice, 0.02 ether);
		assertEq(r.endTime - r.startTime, 2 hours);
		// Old round keeps its own snapshot
		assertEq(lottery.getRound(1).ticketPrice, TICKET_PRICE);
	}

	// ____________________________________________________________
	// buyTickets
	// ____________________________________________________________

	function test_buyTickets_registersPlayerAndPool() public {
		_startRound();

		vm.expectEmit(true, true, false, true);
		emit TicketsPurchased(1, PLAYER_1, 3, 3);
		_buy(PLAYER_1, 3);

		assertEq(lottery.getPlayerTickets(1, PLAYER_1), 3);
		assertEq(lottery.getRoundPlayers(1).length, 3);
		assertEq(lottery.getRoundUniquePlayers(1).length, 1);
		assertEq(lottery.getRound(1).prizePool, 3 * TICKET_PRICE);
		assertEq(address(lottery).balance, 3 * TICKET_PRICE);
	}

	function test_buyTickets_multiplePurchasesDoNotDuplicateUniquePlayer() public {
		_startRound();
		_buy(PLAYER_1, 2);
		_buy(PLAYER_1, 3);

		assertEq(lottery.getPlayerTickets(1, PLAYER_1), 5);
		assertEq(lottery.getRoundUniquePlayers(1).length, 1);
		assertEq(lottery.getRoundPlayers(1).length, 5);
	}

	function test_buyTickets_refundsExcessPayment() public {
		_startRound();
		uint256 balBefore = PLAYER_1.balance;

		vm.prank(PLAYER_1);
		lottery.buyTickets{value: 0.05 ether}(1);

		assertEq(PLAYER_1.balance, balBefore - TICKET_PRICE);
		assertEq(address(lottery).balance, TICKET_PRICE);
	}

	function test_buyTickets_revertsIfExcessRefundFails() public {
		_startRound();
		RejectEther rejecter = new RejectEther();
		vm.deal(address(rejecter), 1 ether);

		vm.expectRevert("Transfer Failed. Please request a refund.");
		rejecter.buy{value: 0.05 ether}(lottery, 1);
	}

	function test_buyTickets_revertsOnZeroQuantity() public {
		_startRound();
		vm.prank(PLAYER_1);
		vm.expectRevert(Lottery.Lottery__ZeroTickets.selector);
		lottery.buyTickets{value: 0}(0);
	}

	function test_buyTickets_revertsIfNoRoundStarted() public {
		// Round 0 was never opened: default state is OPEN but endTime == 0, so the time check rejects it
		vm.prank(PLAYER_1);
		vm.expectRevert(abi.encodeWithSelector(Lottery.Lottery__RoundNotOpen.selector, 0));
		lottery.buyTickets{value: TICKET_PRICE}(1);
	}

	function test_buyTickets_revertsIfInsufficientPayment() public {
		_startRound();
		vm.prank(PLAYER_1);
		vm.expectRevert(abi.encodeWithSelector(Lottery.Lottery__InsufficientPayment.selector, TICKET_PRICE, 2 * TICKET_PRICE));
		lottery.buyTickets{value: TICKET_PRICE}(2);
	}

	function test_buyTickets_revertsIfMaxTicketsExceeded() public {
		_startRound();
		_buy(PLAYER_1, MAX_TICKETS_PER_PLAYER);

		vm.prank(PLAYER_1);
		vm.expectRevert(abi.encodeWithSelector(Lottery.Lottery__MaxTicketsExceeded.selector, MAX_TICKETS_PER_PLAYER + 1, MAX_TICKETS_PER_PLAYER));
		lottery.buyTickets{value: TICKET_PRICE}(1);
	}

	function test_buyTickets_revertsAfterRoundEnded() public {
		_startRound();
		_endRound();

		vm.prank(PLAYER_1);
		vm.expectRevert(abi.encodeWithSelector(Lottery.Lottery__RoundNotOpen.selector, 1));
		lottery.buyTickets{value: TICKET_PRICE}(1);
	}

	function test_buyTickets_revertsWhenRoundCalculating() public {
		uint256 roundId = _startRoundWithPlayers(5);
		_requestDraw(roundId);

		vm.prank(PLAYER_6);
		vm.expectRevert(abi.encodeWithSelector(Lottery.Lottery__RoundNotOpen.selector, 1));
		lottery.buyTickets{value: TICKET_PRICE}(1);
	}

	// ____________________________________________________________
	// requestDraw
	// ____________________________________________________________

	function test_requestDraw_revertsIfRoundStillRunning() public {
		uint256 roundId = _startRoundWithPlayers(5);
		vm.expectRevert(abi.encodeWithSelector(Lottery.Lottery__RoundNotOpen.selector, roundId));
		lottery.requestDraw(roundId);
	}

	function test_requestDraw_movesToCalculatingAndStoresRequest() public {
		uint256 roundId = _startRoundWithPlayers(5);
		_endRound();

		vm.expectEmit(true, true, false, false);
		emit DrawRequested(roundId, 1);
		lottery.requestDraw(roundId);

		Lottery.Round memory r = lottery.getRound(roundId);
		assertEq(uint8(r.state), uint8(Lottery.RoundState.CALCULATING));
		assertEq(r.vrfRequestId, 1);
	}

	function test_requestDraw_canBeCalledByAnyone() public {
		uint256 roundId = _startRoundWithPlayers(5);
		_endRound();
		vm.prank(makeAddr("randomCaller"));
		lottery.requestDraw(roundId);
		assertEq(uint8(lottery.getRound(roundId).state), uint8(Lottery.RoundState.CALCULATING));
	}

	function test_requestDraw_cannotBeCalledTwice() public {
		uint256 roundId = _startRoundWithPlayers(5);
		_requestDraw(roundId);
		vm.expectRevert(abi.encodeWithSelector(Lottery.Lottery__RoundNotOpen.selector, roundId));
		lottery.requestDraw(roundId);
	}

	function test_requestDraw_notEnoughPlayersRefundsRound() public {
		uint256 roundId = _startRoundWithPlayers(2); // min is 3
		_endRound();

		vm.expectEmit(true, false, false, true);
		emit RoundRefunded(roundId, 2);
		lottery.requestDraw(roundId);

		Lottery.Round memory r = lottery.getRound(roundId);
		assertEq(uint8(r.state), uint8(Lottery.RoundState.CLOSED));
		assertTrue(r.refunded);
		assertEq(r.vrfRequestId, 0);
	}

	function test_requestDraw_uniquePlayersNotTicketsCountTowardsMinimum() public {
		uint256 roundId = _startRound();
		_buy(PLAYER_1, 10);
		_buy(PLAYER_2, 10); // 20 tickets but only 2 unique players
		_endRound();
		lottery.requestDraw(roundId);
		assertTrue(lottery.getRound(roundId).refunded);
	}

	// ____________________________________________________________
	// Refunds
	// ____________________________________________________________

	function test_claimRefund_returnsTicketCost() public {
		uint256 roundId = _startRound();
		_buy(PLAYER_1, 2);
		_buy(PLAYER_2, 1);
		_endRound();
		lottery.requestDraw(roundId);

		uint256 balBefore = PLAYER_1.balance;
		vm.expectEmit(true, true, false, true);
		emit RefundClaimed(roundId, PLAYER_1, 2 * TICKET_PRICE);
		vm.prank(PLAYER_1);
		lottery.claimRefund(roundId);

		assertEq(PLAYER_1.balance, balBefore + 2 * TICKET_PRICE);
		assertEq(lottery.getPlayerTickets(roundId, PLAYER_1), 0);
		assertEq(address(lottery).balance, TICKET_PRICE); // PLAYER_2 hasn't claimed
	}

	function test_claimRefund_allPlayersEmptyTheContract() public {
		uint256 roundId = _startRoundWithPlayers(2);
		_endRound();
		lottery.requestDraw(roundId);

		vm.prank(PLAYER_1);
		lottery.claimRefund(roundId);
		vm.prank(PLAYER_2);
		lottery.claimRefund(roundId);

		assertEq(address(lottery).balance, 0);
	}

	function test_claimRefund_cannotClaimTwice() public {
		uint256 roundId = _startRoundWithPlayers(2);
		_endRound();
		lottery.requestDraw(roundId);

		vm.startPrank(PLAYER_1);
		lottery.claimRefund(roundId);
		vm.expectRevert(Lottery.Lottery__NoRefundAvailable.selector);
		lottery.claimRefund(roundId);
		vm.stopPrank();
	}

	function test_claimRefund_revertsForNonParticipant() public {
		uint256 roundId = _startRoundWithPlayers(2);
		_endRound();
		lottery.requestDraw(roundId);

		vm.prank(PLAYER_9);
		vm.expectRevert(Lottery.Lottery__NoRefundAvailable.selector);
		lottery.claimRefund(roundId);
	}

	function test_claimRefund_revertsIfRoundNotRefunded() public {
		uint256 roundId = _startRoundWithPlayers(5);
		vm.prank(PLAYER_1);
		vm.expectRevert(Lottery.Lottery__NoRefundAvailable.selector);
		lottery.claimRefund(roundId);
	}

	function test_claimRefund_revertsIfRecipientRejectsEther() public {
		uint256 roundId = _startRound();
		RejectEther rejecter = new RejectEther();
		vm.deal(address(rejecter), 1 ether);
		rejecter.buy{value: TICKET_PRICE}(lottery, 1);
		_buy(PLAYER_1, 1);
		_endRound();
		lottery.requestDraw(roundId);

		vm.prank(address(rejecter));
		vm.expectRevert("Transfer failed");
		lottery.claimRefund(roundId);
		// state is rolled back, so the ticket is still claimable
		assertEq(lottery.getPlayerTickets(roundId, address(rejecter)), 1);
	}

	// ____________________________________________________________
	// fulfillRandomWords: winners and payouts
	// ____________________________________________________________

	function test_fulfill_distributes50_30_20AfterFee() public {
		uint256 roundId = _startRoundWithPlayers(5);
		uint256 requestId = _requestDraw(roundId);

		uint256 pool = 5 * TICKET_PRICE;
		uint256 fee = (pool * PROTOCOL_FEE_BPS) / 10_000;
		uint256 dist = pool - fee;
		uint256 p1 = (dist * 5000) / 10_000;
		uint256 p2 = (dist * 3000) / 10_000;
		uint256 p3 = dist - p1 - p2;

		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));

		Lottery.Round memory r = lottery.getRound(roundId);
		assertEq(uint8(r.state), uint8(Lottery.RoundState.CLOSED));
		assertEq(r.protocolFeeCollected, fee);
		assertEq(r.payouts[0], p1);
		assertEq(r.payouts[1], p2);
		assertEq(r.payouts[2], p3);
		assertEq(p1 + p2 + p3 + fee, pool, "no dust lost");
		assertEq(lottery.getAccumulatedFees(), fee);
		assertEq(address(lottery).balance, fee, "only fees stay in the contract");
	}

	function test_fulfill_winnersAreUniqueParticipantsAndGetPaid() public {
		address[5] memory p = _players();
		uint256[5] memory balsBefore;
		uint256 roundId = _startRound();
		for (uint256 i; i < 5; i++) {
			_buy(p[i], 1);
			balsBefore[i] = p[i].balance; // after paying for the ticket
		}
		uint256 requestId = _requestDraw(roundId);
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));

		address[3] memory winners = lottery.getRoundWinners(roundId);
		uint256[3] memory payouts = lottery.getRoundPayouts(roundId);

		assertTrue(winners[0] != winners[1] && winners[1] != winners[2] && winners[0] != winners[2], "winners must be unique");

		uint256 totalPaid;
		for (uint256 i; i < 3; i++) {
			bool isPlayer;
			for (uint256 j; j < 5; j++) {
				if (winners[i] == p[j]) {
					isPlayer = true;
					assertEq(p[j].balance, balsBefore[j] + payouts[i]);
				}
			}
			assertTrue(isPlayer, "winner must be a participant");
			totalPaid += payouts[i];
		}
		assertEq(totalPaid, lottery.getRound(roundId).prizePool - lottery.getRound(roundId).protocolFeeCollected);
	}

	function test_fulfill_emitsEvents() public {
		uint256 roundId = _startRoundWithPlayers(5);
		uint256 requestId = _requestDraw(roundId);
		uint256 fee = (5 * TICKET_PRICE * PROTOCOL_FEE_BPS) / 10_000;

		vm.expectEmit(true, false, false, true);
		emit ProtocolFeeCollected(roundId, fee);
		// WinnersSelected: only check the indexed roundId topic
		vm.expectEmit(true, false, false, false);
		emit WinnersSelected(roundId, [address(0), address(0), address(0)], [uint256(0), 0, 0]);
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));
	}

	function test_fulfill_resolvesCollisionsWhenRandomWordsAreEqual() public {
		uint256 roundId = _startRoundWithPlayers(5);
		uint256 requestId = _requestDraw(roundId);

		// Identical seeds force the collision / re-hash path
		uint256[] memory words = new uint256[](3);
		words[0] = 7;
		words[1] = 7;
		words[2] = 7;
		vrfCoordinatorMock.fulfillRandomWordsWithOverride(requestId, address(lottery), words);

		address[3] memory w = lottery.getRoundWinners(roundId);
		assertTrue(w[0] != address(0) && w[1] != address(0) && w[2] != address(0));
		assertTrue(w[0] != w[1] && w[1] != w[2] && w[0] != w[2]);
	}

	function test_fulfill_deterministicWithOverrideWords() public {
		uint256 roundId = _startRoundWithPlayers(5);
		uint256 requestId = _requestDraw(roundId);

		uint256[] memory words = new uint256[](3);
		words[0] = 0; // ticket index 0 -> PLAYER_1
		words[1] = 1; // ticket index 1 -> PLAYER_2
		words[2] = 2; // ticket index 2 -> PLAYER_3
		vrfCoordinatorMock.fulfillRandomWordsWithOverride(requestId, address(lottery), words);

		address[3] memory w = lottery.getRoundWinners(roundId);
		assertEq(w[0], PLAYER_1);
		assertEq(w[1], PLAYER_2);
		assertEq(w[2], PLAYER_3);
	}

	function test_fulfill_moreTicketsMeansMoreWins() public {
		// PLAYER_1 holds 10 of 14 tickets; over many draws they should win 1st place far more often
		uint256 p1Wins;
		uint256 rounds = 30;
		// each mock draw costs ~62.5 LINK; top up the subscription for 30 draws
		vrfCoordinatorMock.fundSubscription(subscriptionId, 1000 ether);
		for (uint256 n; n < rounds; n++) {
			uint256 roundId = _startRound();
			_buy(PLAYER_1, 10);
			_buy(PLAYER_2, 1);
			_buy(PLAYER_3, 1);
			_buy(PLAYER_4, 1);
			_buy(PLAYER_5, 1);
			uint256 requestId = _requestDraw(roundId);

			uint256[] memory words = new uint256[](3);
			for (uint256 i; i < 3; i++) {
				words[i] = uint256(keccak256(abi.encode(n, i)));
			}
			vrfCoordinatorMock.fulfillRandomWordsWithOverride(requestId, address(lottery), words);
			if (lottery.getRoundWinners(roundId)[0] == PLAYER_1) p1Wins++;
			// PLAYER_1 needs enough ETH for the next round
			vm.deal(PLAYER_1, 10 ether);
		}
		// Expected ~71% (10/14). Very loose bound to keep the test stable.
		assertGt(p1Wins, rounds / 2);
	}

	function test_fulfill_twoUniquePlayersSplit60_40() public {
		vm.prank(OWNER);
		lottery.setMinPlayers(2);
		uint256 roundId = _startRoundWithPlayers(2);
		uint256 requestId = _requestDraw(roundId);
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));

		uint256 dist = 2 * TICKET_PRICE - (2 * TICKET_PRICE * PROTOCOL_FEE_BPS) / 10_000;
		uint256[3] memory payouts = lottery.getRoundPayouts(roundId);
		address[3] memory w = lottery.getRoundWinners(roundId);

		assertEq(payouts[0], (dist * 6000) / 10_000);
		assertEq(payouts[1], dist - payouts[0]);
		assertEq(payouts[2], 0);
		assertTrue(w[0] != w[1]);
		assertEq(w[2], address(0));
	}

	function test_fulfill_singlePlayerGetsWholeDistributablePool() public {
		vm.prank(OWNER);
		lottery.setMinPlayers(1);
		uint256 roundId = _startRound();
		_buy(PLAYER_1, 4);
		uint256 requestId = _requestDraw(roundId);
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));

		uint256 pool = 4 * TICKET_PRICE;
		uint256 dist = pool - (pool * PROTOCOL_FEE_BPS) / 10_000;
		assertEq(lottery.getRoundWinners(roundId)[0], PLAYER_1);
		assertEq(lottery.getRoundPayouts(roundId)[0], dist);
	}

	function test_fulfill_zeroFeeSendsEverythingToWinners() public {
		vm.prank(OWNER);
		lottery.setProtocolFeeBps(0);
		uint256 roundId = _startRoundWithPlayers(5);
		uint256 requestId = _requestDraw(roundId);
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));

		assertEq(lottery.getAccumulatedFees(), 0);
		assertEq(address(lottery).balance, 0);
	}

	function test_fulfill_roundStaysCalculatingIfWinnerRejectsEther() public {
		uint256 roundId = _startRound();
		for (uint256 i; i < 3; i++) {
			RejectEther r = new RejectEther();
			vm.deal(address(r), 1 ether);
			r.buy{value: TICKET_PRICE}(lottery, 1);
		}
		uint256 requestId = _requestDraw(roundId);

		// The mock swallows the callback revert (success = false), so the call itself doesn't revert
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));

		Lottery.Round memory r2 = lottery.getRound(roundId);
		assertEq(uint8(r2.state), uint8(Lottery.RoundState.CALCULATING));
		assertEq(lottery.getAccumulatedFees(), 0, "state rolled back");
		assertEq(address(lottery).balance, 3 * TICKET_PRICE, "funds untouched");
	}

	function test_rawFulfillRandomWords_onlyCoordinator() public {
		uint256 roundId = _startRoundWithPlayers(5);
		uint256 requestId = _requestDraw(roundId);

		uint256[] memory words = new uint256[](3);
		vm.prank(PLAYER_1);
		vm.expectRevert(abi.encodeWithSelector(VRFConsumerBaseV2Plus.OnlyCoordinatorCanFulfill.selector, PLAYER_1, address(vrfCoordinatorMock)));
		lottery.rawFulfillRandomWords(requestId, words);
	}

	function test_fulfill_cannotFulfillTwice() public {
		uint256 roundId = _startRoundWithPlayers(5);
		uint256 requestId = _requestDraw(roundId);
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));

		vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));
	}

	function test_fullFlow_multipleRoundsAreIndependent() public {
		_completeRound();
		uint256 feesAfterFirst = lottery.getAccumulatedFees();

		uint256 round2 = _startRoundWithPlayers(4);
		assertEq(round2, 2);
		assertEq(lottery.getPlayerTickets(2, PLAYER_1), 1);
		assertEq(lottery.getRound(2).prizePool, 4 * TICKET_PRICE);

		uint256 requestId = _requestDraw(round2);
		vrfCoordinatorMock.fulfillRandomWords(requestId, address(lottery));

		assertEq(uint8(lottery.getRound(2).state), uint8(Lottery.RoundState.CLOSED));
		assertGt(lottery.getAccumulatedFees(), feesAfterFirst);
		assertEq(address(lottery).balance, lottery.getAccumulatedFees());
	}

	function test_fullFlow_refundedRoundThenNewRound() public {
		uint256 roundId = _startRoundWithPlayers(2);
		_endRound();
		lottery.requestDraw(roundId);

		// A refunded round is CLOSED, so a new one can start
		uint256 next = _startRound();
		assertEq(next, 2);
	}

	// ____________________________________________________________
	// Admin
	// ____________________________________________________________

	function test_admin_settersUpdateConfigAndEmit() public {
		vm.startPrank(OWNER);

		vm.expectEmit(false, false, false, true);
		emit ConfigUpdated(0.5 ether, ROUND_DURATION, MAX_TICKETS_PER_PLAYER, MIN_PLAYER, PROTOCOL_FEE_BPS);
		lottery.setTicketPrice(0.5 ether);

		lottery.setRoundDuration(2 days);
		lottery.setMaxTicketsPerPlayer(50);
		lottery.setMinPlayers(5);
		lottery.setProtocolFeeBps(1000);
		vm.stopPrank();

		Lottery.LotteryConfig memory cfg = lottery.getConfig();
		assertEq(cfg.ticketPrice, 0.5 ether);
		assertEq(cfg.roundDuration, 2 days);
		assertEq(cfg.maxTicketsPerPlayer, 50);
		assertEq(cfg.minPlayers, 5);
		assertEq(cfg.protocolFeeBps, 1000);
	}

	function test_admin_settersRevertOnInvalidValues() public {
		vm.startPrank(OWNER);
		vm.expectRevert(Lottery.Lottery__InvalidTicketPrice.selector);
		lottery.setTicketPrice(0);
		vm.expectRevert(Lottery.Lottery__InvalidRoundDuration.selector);
		lottery.setRoundDuration(0);
		vm.expectRevert(Lottery.Lottery__InvalidMaxTickets.selector);
		lottery.setMaxTicketsPerPlayer(0);
		vm.expectRevert(Lottery.Lottery__InvalidMinPlayers.selector);
		lottery.setMinPlayers(0);
		vm.expectRevert(Lottery.Lottery__InvalidProtocolFee.selector);
		lottery.setProtocolFeeBps(1001);
		vm.stopPrank();
	}

	function test_admin_settersOnlyOwner() public {
		vm.startPrank(PLAYER_1);
		vm.expectRevert("Only callable by owner");
		lottery.setTicketPrice(1 ether);
		vm.expectRevert("Only callable by owner");
		lottery.setRoundDuration(1);
		vm.expectRevert("Only callable by owner");
		lottery.setMaxTicketsPerPlayer(1);
		vm.expectRevert("Only callable by owner");
		lottery.setMinPlayers(1);
		vm.expectRevert("Only callable by owner");
		lottery.setProtocolFeeBps(1);
		vm.expectRevert("Only callable by owner");
		lottery.withdrawFees(PLAYER_1);
		vm.stopPrank();
	}

	function test_admin_configChangeDoesNotAffectOpenRound() public {
		_startRound();
		vm.prank(OWNER);
		lottery.setTicketPrice(1 ether);

		// Still the old price for the open round
		_buy(PLAYER_1, 1);
		assertEq(lottery.getRound(1).prizePool, TICKET_PRICE);
	}

	// ____________________________________________________________
	// withdrawFees
	// ____________________________________________________________

	function test_withdrawFees_sendsAccumulatedFees() public {
		_completeRound();
		uint256 fees = lottery.getAccumulatedFees();
		address treasury = makeAddr("treasury");

		vm.expectEmit(true, false, false, true);
		emit FeesWithdrawn(treasury, fees);
		vm.prank(OWNER);
		lottery.withdrawFees(treasury);

		assertEq(treasury.balance, fees);
		assertEq(lottery.getAccumulatedFees(), 0);
		assertEq(address(lottery).balance, 0);
	}

	function test_withdrawFees_revertsWhenNothingToWithdraw() public {
		vm.prank(OWNER);
		vm.expectRevert(Lottery.Lottery__NothingToWithdraw.selector);
		lottery.withdrawFees(OWNER);
	}

	function test_withdrawFees_cannotWithdrawTwice() public {
		_completeRound();
		vm.startPrank(OWNER);
		lottery.withdrawFees(OWNER);
		vm.expectRevert(Lottery.Lottery__NothingToWithdraw.selector);
		lottery.withdrawFees(OWNER);
		vm.stopPrank();
	}

	function test_withdrawFees_revertsIfRecipientRejectsEther() public {
		_completeRound();
		RejectEther rejecter = new RejectEther();
		vm.prank(OWNER);
		vm.expectRevert("Transfer Failed. Please withdraw manually.");
		lottery.withdrawFees(address(rejecter));
		assertGt(lottery.getAccumulatedFees(), 0, "fees preserved after failed withdrawal");
	}

	// ____________________________________________________________
	// Fuzz
	// ____________________________________________________________

	function testFuzz_buyTickets_poolMatchesQuantity(uint256 qty, uint256 extra) public {
		qty = bound(qty, 1, MAX_TICKETS_PER_PLAYER);
		extra = bound(extra, 0, 1 ether);
		_startRound();

		uint256 balBefore = PLAYER_1.balance;
		vm.prank(PLAYER_1);
		lottery.buyTickets{value: TICKET_PRICE * qty + extra}(qty);

		assertEq(lottery.getRound(1).prizePool, TICKET_PRICE * qty);
		assertEq(lottery.getPlayerTickets(1, PLAYER_1), qty);
		assertEq(PLAYER_1.balance, balBefore - TICKET_PRICE * qty);
		assertEq(address(lottery).balance, TICKET_PRICE * qty);
	}

	function testFuzz_buyTickets_neverExceedsMax(uint256 qty) public {
		qty = bound(qty, MAX_TICKETS_PER_PLAYER + 1, 1000);
		_startRound();
		vm.deal(PLAYER_1, 1000 ether);
		vm.prank(PLAYER_1);
		vm.expectRevert(abi.encodeWithSelector(Lottery.Lottery__MaxTicketsExceeded.selector, qty, MAX_TICKETS_PER_PLAYER));
		lottery.buyTickets{value: TICKET_PRICE * qty}(qty);
	}

	function testFuzz_fulfill_conservesFunds(uint256 w0, uint256 w1, uint256 w2, uint8 feeSeed) public {
		uint16 fee = uint16(bound(feeSeed, 0, 1000));
		vm.prank(OWNER);
		lottery.setProtocolFeeBps(fee);

		uint256 roundId = _startRound();
		address[5] memory p = _players();
		for (uint256 i; i < 5; i++) {
			_buy(p[i], i + 1); // uneven ticket distribution
		}
		uint256 requestId = _requestDraw(roundId);

		uint256[] memory words = new uint256[](3);
		words[0] = w0;
		words[1] = w1;
		words[2] = w2;
		vrfCoordinatorMock.fulfillRandomWordsWithOverride(requestId, address(lottery), words);

		Lottery.Round memory r = lottery.getRound(roundId);
		assertEq(uint8(r.state), uint8(Lottery.RoundState.CLOSED));

		address[3] memory w = lottery.getRoundWinners(roundId);
		assertTrue(w[0] != w[1] && w[1] != w[2] && w[0] != w[2], "unique winners");
		assertEq(r.payouts[0] + r.payouts[1] + r.payouts[2] + r.protocolFeeCollected, r.prizePool);
		assertEq(address(lottery).balance, lottery.getAccumulatedFees());
	}

	function testFuzz_refund_neverPaysMoreThanDeposited(uint8 qty1, uint8 qty2) public {
		uint256 q1 = bound(qty1, 1, MAX_TICKETS_PER_PLAYER);
		uint256 q2 = bound(qty2, 1, MAX_TICKETS_PER_PLAYER);
		uint256 roundId = _startRound();
		_buy(PLAYER_1, q1);
		_buy(PLAYER_2, q2);
		_endRound();
		lottery.requestDraw(roundId);

		vm.prank(PLAYER_1);
		lottery.claimRefund(roundId);
		vm.prank(PLAYER_2);
		lottery.claimRefund(roundId);

		assertEq(address(lottery).balance, 0);
		assertEq(PLAYER_1.balance, 10 ether);
		assertEq(PLAYER_2.balance, 10 ether);
	}

}
