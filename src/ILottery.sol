// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ILottery {
    struct LotteryState {
        uint256 lpPool;
        uint256 userPool;
        uint256 lastDrawBlock;
        uint256 winningNumber;
        bool isActive;
    }

    struct User {
        // Total tickets purchased by the user for current lottery, multiplied by 10000, resets each lottery
        uint256 ticketsPurchasedTotalBps;
        // Tracks the total win amount (how much the user can withdraw)
        uint256 winningsClaimable;
        // Whether or not the user is participating in the current lottery
        bool active;
    }

    struct LP {
        uint256 principal;
        uint256 stake;
        uint256 riskPercentage; // From 0 to 100
        // Whether or not the LP has principal stored in the contract
        bool active;
    }

    event EntropyResult(uint64 sequenceNumber, bytes32 randomNumber);

/*     function runLottery() external;

    function purchaseTickets() external;

    function withdrawWinnings() external;

    function withdrawReferralFees() external;

    function withdrawProtocolFees() external;

    function withdrawAllLP() external;

    function lpDeposit() external;

    function drawWinner() external;

    function withdrawLPFee() external;

    function withdrawUserPoolForLP() external; */
}
