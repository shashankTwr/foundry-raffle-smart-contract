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

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts@1.1.1/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";


/**
 * @title  Raffle
 * @author Shashank Tiwari
 * @notice This contract is for creating a simple raffle
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle {
    /**
     * Errors
     */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__NotEnoughTimeHasPassed();

    uint256 private immutable i_entranceFee;
    // @dev The duration of the lottery in seconds
    uint256 private immutable i_interval;

    uint256 private s_lastTimeStamp;

    // What data structure should we use? How to keep track of all players?
    address payable[] private s_players;

    /**
     * Events
     */
    event RaffleEntered(address indexed player);

    constructor(uint256 _entranceFee, uint256 interval) {
        i_entranceFee = _entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, SendMoreToEnterRaffle());
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        s_players.push(payable(msg.sender));
        // 1. Makes migration easier
        // 2. Makes front end "indexing" easier
        emit RaffleEntered(msg.sender);
    }

    // 1. Get a random number
    // 2. Use random number to pick a player
    // 3. Be automatically called
    function pickWinner() external {
        // check to see if enough time has passed
        if (block.timestamp - s_lastTimeStamp < i_interval) {
            revert Raffle__NotEnoughTimeHasPassed();
        }
        // Get our random number from ChainLink vrf 2.5
        // 1. Request RNG
        // 2. Get RNG
        uint256 requestID = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true})) // new parameter
            })
        );
    }

    /**
     * Getter functions
     */
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }
}
