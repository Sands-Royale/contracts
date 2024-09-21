# Uniswap V4 Lottery Smart Contract

This project implements a lottery system using Uniswap V4 hooks. It consists of two main contracts: `Lottery.sol` and `LotteryManager.sol`.

## Overview

The lottery system allows for two types of participants:
1. Liquidity Providers (LPs)
2. Lottery Players

LPs provide liquidity to the lottery pool, while players buy lottery tickets. The system uses Uniswap V4 hooks to manage the pools and determine the outcomes.

## Deployments:
We are using Base Sepolia.

  Manager deployed to:  0xe2556948701831C7174aa7207FdcB28A092737F9
  Lottery deployed to:  0x99c1bC023bfaF144316794bbd51d3b357693eF1e

## Smart Contracts

### Lottery.sol

This contract implements the core lottery functionality:

- LPs provide liquidity to the lottery (LP pool)
- A percentage of the LP pool is used for the lottery based on risk appetite
- Players buy lottery tickets (user pool)
- Winning scenarios:
  - If user pool > LP pool: winner gets the user pool, LPs get back the LP pool
  - If user pool <= LP pool and a player wins: winner gets the total LP pool, LPs get the user pool
  - If no winning ticket is found: LPs get both the user pool and the LP pool

The contract uses a Uniswap V4 pool with hooks, where one token represents the winnings (e.g., USDC) and another represents the players' bets.

### LotteryManager.sol

This contract manages the deployment of lotteries and controls liquidity addition and removal:

- Deploys new lottery contracts
- Mints lottery tokens when LPs deposit USDC
- Burns lottery tokens when LPs remove liquidity

## Setup and Installation

1. Install Foundry: https://book.getfoundry.sh/getting-started/installation
2. Clone the repository:
   ```
   git clone https://github.com/sands-royale/contracts.git
   cd contracts
   ```
3. Install dependencies:
   ```
   forge install
   ```

## Compilation

Compile the smart contracts using Foundry:

```
forge build
```

## Usage

1. Deploy the `LotteryManager` contract.
2. Use the `LotteryManager` to create new lottery instances.
3. LPs can add liquidity through the `LotteryManager`.
4. Players can participate in the lottery by buying tickets through the `Lottery` contract.
5. The lottery results are determined using Uniswap V4 hooks.

## License

[MIT License](LICENSE)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.