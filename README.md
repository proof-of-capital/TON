# Proof of Capital

**Available in other languages:** [Русский](README.ru.md) | [Español](README.es.md)

---

Proof of Capital is a smart market-making technology (smart contract) that protects the interests of all holders. Creators transfer all the free issuance of their asset to the contract, and coins are released only for TON, which remains on the contract as collateral. The contract can both sell coins, receiving collateral from upper levels, and accept the return of coins to release collateral from lower levels, thereby increasing the minimum price of the asset.

---

## Contents

- [Project Structure - Blueprint](#project-structure---blueprint)
- [Running the Contract](#running-the-contract)
  - [Add a New Contract](#add-a-new-contract)
  - [Build](#build)
  - [Testing](#testing)
  - [Deployment or Running a Script](#deployment-or-running-a-script)
- [Main Provisions](#main-provisions)
  - [Variables Defined During Initialization and Deployment of the Contract](#variables-defined-during-initialization-and-deployment-of-the-contract)
  - [Description of Variables](#description-of-variables)
- [Principle of Contract Operation](#principle-of-contract-operation)
  - [Contract Functions](#contract-functions)
  - [Important Notes](#important-notes)
- [Accessing Getter Functions](#accessing-getter-functions)
- [Contact Information](#contact-information)

---

## Project Structure - Blueprint

- `contracts` — source code of all smart contracts of the project and their dependencies.
- `wrappers` — wrappers (classes implementing `Contract` from ton-core) for contracts, including primitives for [de]serialization and compilation functions.
- `tests` — tests for contracts.
- `scripts` — scripts used in the project, mainly for deployment.

## Running the Contract

### Add a New Contract

```bash
npx blueprint create ContractName
# or
yarn create ton ContractName
```
When creating, select `An empty contract (TACT)`.

### Build

```bash
npx blueprint build
# or
yarn blueprint build
```

### Testing

```bash
npx blueprint test
# or
yarn blueprint test
```

### Deployment or Running a Script

```bash
npx blueprint run
# or
yarn blueprint run
```

---

## Main Provisions

### Variables Defined During Initialization and Deployment of the Contract

During initialization and deployment of the contract in Tact, the following variables are set, which define the main settings of the contract and its initial state:

### Description of Variables

| Variable                              | Data Type         | Description                                                         |
|---------------------------------------|-------------------|---------------------------------------------------------------------|
| **owner**                             | `Address`         | Address of the contract owner.                                      |
| **marketMakerAddress**                | `Address`         | Address of the market maker.                                        |
| **jettonMasterAddress**               | `Address`         | Address of the jetton master contract.                              |
| **returnWalletAddress**               | `Address`         | Address of the wallet for returns.                                  |
| **royaltyWalletAddress**              | `Address`         | Address of the royalty wallet.                                      |
| **lockEndTime**                       | `Int as uint64`   | End time of the lock (in seconds since UNIX epoch).                 |
| **initialPricePerToken**              | `Int as coins`    | Initial price per jetton.                                           |
| **firstLevelJettonQuantity**          | `Int as coins`    | Number of jettons at the first level.                               |
| **priceIncrementMultiplier**          | `Int as uint16`   | Multiplier for increasing the price per jetton.                     |
| **levelIncreaseMultiplier**           | `Int as uint16`   | Multiplier for increasing the level.                                |
| **trendChangeStep**                   | `Int as uint8`    | Step for trend change.                                              |
| **levelIncreaseMultiplierafterTrend** | `Int as uint16`   | Multiplier for decreasing the level after trend change.             |
| **profitPercentage**                  | `Int as uint16`   | Profit percentage.                                                  |

---

## Principle of Contract Operation

The Proof of Capital contract is designed to manage the issuance of jettons backed by capital, with transparent conditions for emission and buyback.

### Contract Functions

1. **Deployment and Initial Setup:**
   - After deploying the contract, the creator replenishes it with jettons and sets a lock for **six months** or **10 minutes** (for initial testing of the contract).
   - The creator can extend the **lock** for an additional period: **six months** or **10 minutes**.

2. **Interaction with the Contract:**
   - **Market Maker:**
     - During the lock period, only the market maker can exchange tokens with the contract.
     - Market maker has the right to buy and sell jettons, balancing the price on the contract with prices in pools on DEX.
   - **Other Users:**
     - **Two months before the end of the lock**, all users can interact with the contract.
     - They can return the jettons purchased from the contract back to the contract in exchange for collateral.
   - **Return Wallet:**
     - A special wallet from which tokens are returned to the contract, releasing collateral from lower levels.
     - This is an alternative to the burning procedure, aiming to use the earned tokens in the future as capitalization grows.


3. **Lock Expiration:**
   - After the lock period ends, the creator can withdraw all tokens and all TON from the contract.

### Important Notes

- **Use Getter Functions:**
  - When working with the contract, always use the getter functions to check the results of your operations **before** executing them.
  - This will help avoid unexpected results.

- **Interacting with the Contract:**
  - **Never send coins (tokens) directly from your wallet to the contract.**
    - If you send tokens without calling the corresponding functions, the contract can't process the transaction, and your coins will be lost.
  - If you send TON directly:
    - The contract will reject the operation if more than two months remain until the end of the lock.
    - The contract can send you coins (jettons) if less than two months remain until the end of the lock.
    - **Be sure to check the results of the getter functions before interacting with the contract.** If the contract does not have enough jettons, it will send you all that remains. If no coins remain, the TON will be credited to the contract’s balance.


- **Features of Selling Jetton Remainders:**
  - If you attempt to return more jettons than the contract is set to buy back, you will receive the entire remaining TON balance reserved for buybacks, while the excess jettons will be transferred to the contract’s balance.
  - **Be sure to study the output of the `jetton_available` getter function before sending jettons to the contract.**

- **Profit and Commissions:**
  - **20%** of the profit is directed to the **Royalty** wallet specified on the website [proofofcapital.org](https://proofofcapital.org).
  - **80%** is allocated to the creator’s wallet for development and marketing purposes.

---

## Accessing Getter Functions

To obtain data on the current state of the contract and the results of internal functions, you can use the getter functions:

1. Go to **TON Viewer** or a similar tool.
2. Open the **Methods** tab.
3. In the **Arbitrary method** field, enter the name of the getter function.
4. If necessary, add arguments.
5. Click the **Execute** button to perform the request.

**We recommend** always using the getter functions before performing operations to check the expected results.

---

## Contact Information

For any questions, please contact us via the contact details listed on the website [proofofcapital.org](https://proofofcapital.org).

We have passed the second audit, which will be published for the current version of the contract. We are currently preparing to release the next version, which will take into account all auditors' recommendations. An example operating on this version of the contract is available [at this link](https://tonviewer.com/EQBGN2w9fUVNfJ0IBKDQ2vVy6S_lDug4q1UYdRhkFA-r_POK).

---

**Attention!** Sending coins directly to the contract and conducting transactions without prior analysis of the getter functions' output may lead to loss of funds. Always check the address and use the provided methods for interacting with the contract.