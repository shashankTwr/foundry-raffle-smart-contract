// Solidity Layout
// 	Pragma
// 	import
// 	Interfaces
// 	libraries
// 	contracts
// 		Type declarations
// 		state variables
// 		events
// 		modifiers
// 		functions
// 			constructor
// 			recieve
// 			fallback
// 			external
// 			public
// 			internal
// 			private

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title  Raffle
 * @author Shashank Tiwari
 * @notice This contract is for creating a simple raffle
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    /**
     * Errors
     */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__NotEnoughTimeHasPassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    /**
     * Type declarations
     */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /**
     * State variables
     */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    // @dev The duration of the lottery in seconds
    uint256 private immutable i_interval;
    bytes32 private immutable i_gasLane;
    uint256 private immutable i_subId;
    uint32 private immutable i_callbackGasLimit;

    uint256 private s_lastTimeStamp;

    // What data structure should we use? How to keep track of all players?
    address payable[] private s_players;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /**
     * Events
     */
    event RaffleEntered(address indexed player);
    event RaffleWinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 _entranceFee,
        uint256 interval,
        address vrfCoordinatorv2,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinatorv2) {
        i_entranceFee = _entranceFee;
        i_interval = interval;
        i_gasLane = gasLane;
        i_subId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        // require(msg.value >= i_entranceFee, SendMoreToEnterRaffle());
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        // 1. Makes migration easier
        // 2. Makes front end "indexing" easier
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is the function that the chainlink nodes will call to
     * if the lottery is ready to have winner picked
     * the following should be true in order for upkeep needed to be true
     * 1. The time interval has passed between raffle runs
     * 2. THe lottery is open
     * 3. GThe contract has eth
     * 4. Implicity your subscription has LINK
     * @param -ignored
     * @return upkeepNeeded
     * @return -ignored
     */
    function checkUpkeep(bytes memory /*checkdata */ )
        /**
         * data
         */
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasEth = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasEth && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // 1. Get a random number
    // 2. Use random number to pick a player
    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */ ) external override {
        // check to see if enough time has passed
        (bool upKeepNeeded,) = checkUpkeep("");
        if (!upKeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState = RaffleState.CALCULATING;

        // s_keyHash -> gas lane key hash value
        // s_subId -> subscription id
        // requestConfirmations -> number of confirmations
        // callbackGasLimit -> gas limit
        // numWords -> number of words
        // extraArgs -> new parameter
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_gasLane,
            subId: i_subId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // set nativePayment to true to pay for VRF requests with sepolia ETH instead of link
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            ) // new parameter
        });

        // Get our random number from ChainLink vrf 2.5
        // 1. Request RNG
        // 2. Get RNG
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);

        // Quiz.. Is this redundant?
        emit RequestedRaffleWinner(requestId);
    }

    // CEI: Checks, Effects, Interactions Pattern
    function fulfillRandomWords(uint256, /* requestId */ uint256[] calldata randomWords) internal override {
        // Checks : More gas efficient
        // Conditionals

        // Effect (Internal Contract State)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        // State updates
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0); // size 0 array
        s_lastTimeStamp = block.timestamp;
        emit RaffleWinnerPicked(recentWinner);

        // Interactions (external contract interactions)
        (bool success,) = recentWinner.call{value: address(this).balance}("");

        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter functions
     */
    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayers() external view returns (address payable[] memory) {
        address payable[] memory players = s_players;
        return players;
    }

    function getPlayerByIndex(uint256 indexOfPlayers) external view returns (address payable) {
        return s_players[indexOfPlayers];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }
}
