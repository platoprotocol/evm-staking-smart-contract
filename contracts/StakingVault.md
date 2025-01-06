The `StakingVault` contract is a Solidity smart contract designed for staking ERC20 tokens. It allows users to stake tokens and earn rewards based on an Annual Percentage Yield (APY) over a specified duration. The contract inherits from `Ownable`, `Pausable`, and `ReentrancyGuard` from the OpenZeppelin library to provide ownership control, pausing functionality, and protection against reentrancy attacks, respectively.

The contract defines several data structures to manage staking. The `APY` struct holds the percentage and duration of the APY. The `DepositDetails` struct contains information about each deposit, including the APY, amount, and timestamp. The `UserInfo` struct keeps track of the total staked amount and a list of deposits for each user.

The contract uses the `SafeERC20` library to safely interact with ERC20 tokens. It has two immutable variables, `stakingToken` and `rewardToken`, which represent the token being staked and the token used for rewards. The contract also maintains various state variables, including the start timestamp, fee address, total staked amount, exit penalty percentage, and withdrawal fee.

The constructor initializes the contract with the token address, fee address, APY percentage, APY duration, exit penalty percentage, and withdrawal fee. It sets the initial values for these parameters and records the start timestamp.

The `stake` function allows users to stake a specified amount of tokens for a given duration. It checks that the amount and duration are valid, transfers the tokens to the contract, and updates the user's staking information. The `unstake` function allows users to unstake their tokens, either all at once or by specifying an index. It calculates the reward based on the elapsed time and APY, applies any penalties or fees, and transfers the tokens back to the user.

The contract also includes functions for managing the staking parameters, such as starting and stopping rewards, updating APY options, and handling emergency withdrawals. Additionally, it provides several view functions to retrieve information about the staking status, such as the available APY durations, staked tokens, and rewards.