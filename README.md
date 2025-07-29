# Proof of Capital

**Available in other languages:** [Русский](README.ru.md) | [Español](README.es.md)

---

Proof of Capital is a smart market-making technology (smart contract) that protects the interests of all holders.

Creators transfer all of their asset's emission to the contract, and coins are released only in exchange for TON or, when support is enabled, any other token, which remain in the contract as collateral. The contract allows both selling coins, receiving collateral from the upper levels, and returning coins to release collateral from the lower levels, thereby increasing the minimum price per asset.

The contract supports launching both from scratch and taking into account the asset's previous history. To do this, you can set an offset parameter—the equivalent of previously sold coins—which allows the contract to start operation from the desired price level and collateral balance. This is especially important for existing projects transitioning to Proof of Capital.

---

## Table of Contents

- [Proof of Capital](#proof-of-capital)
  - [Table of Contents](#table-of-contents)
  - [Blueprint Project Structure](#blueprint-project-structure)
  - [Running the Contract](#running-the-contract)
    - [Add a New Contract](#add-a-new-contract)
    - [Build](#build)
    - [Deployment or Running a Script](#deployment-or-running-a-script)
  - [Key Provisions](#key-provisions)
    - [Variables Set During Initialization and Deployment](#variables-set-during-initialization-and-deployment)
    - [Variable Descriptions](#variable-descriptions)
  - [Contract Operation Principle](#contract-operation-principle)
    - [Contract Functions](#contract-functions)
    - [Important Notes](#important-notes)
  - [Calling Getter Functions](#calling-getter-functions)
  - [Contact Information](#contact-information)

---

## Blueprint Project Structure

- `contracts` — source code of all the project's smart contracts and their dependencies.
- `wrappers` — wrappers (classes implementing `Contract` from ton-core) for contracts, including primitives for [de]serialization and compilation functions.
- `tests` — tests for the contracts.
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

### Deployment or Running a Script

```bash
npx blueprint run
# or
yarn blueprint run
```

---

## Key Provisions

### Variables Set During Initialization and Deployment

During initialization and deployment of the contract in Tact, the following variables are set, which define the main settings of the contract and its initial state:

### Variable Descriptions

| Variable                                  | Data Type        | Description                                                               |
|-------------------------------------------|------------------|---------------------------------------------------------------------------|
| **owner**                                 | `Address`        | Address of the contract owner.                                            |
| **marketMakerAddress**                    | `Address`        | Address of the market maker.                                              |
| **launchJettonMasterAddress**                   | `Address`        | Address of the jetton master contract.                                    |
| **returnWalletAddress**                   | `Address`        | Address of the wallet for returning funds.                                |
| **royaltyWalletAddress**                  | `Address`        | Address of the royalty wallet.                                            |
| **lockEndTime**                           | `Int as uint64`  | Lock end time (in seconds since the UNIX epoch).                          |
| **initialPricePerToken**                  | `Int as coins`   | Initial price per jetton.                                                 |
| **firstLevelJettonQuantity**              | `Int as coins`   | Quantity of jettons at the first level.                                   |
| **priceIncrementMultiplier**              | `Int as uint16`  | Multiplier for increasing the price per jetton.                           |
| **levelIncreaseMultiplier**               | `Int as uint16`  | Multiplier for increasing the level.                                      |
| **trendChangeStep**                       | `Int as uint8`   | Step for changing the trend.                                              |
| **levelDecreaseMultiplierafterTrend**     | `Int as uint16`  | Multiplier for decreasing the level after a trend change.                 |
| **profitPercentage**                      | `Int as uint16`  | Profit percentage.                                                        |
| **offsetJettons**                         | `Int as coins`   | Number of previously sold jettons (historical offset).                    |
| **controlPeriod**                         | `Int as uint32`  | Duration of the "unlock window" in UNIX seconds.                          |
| **jettonSupport**                         | `Bool`           | Enables purchasing jettons with other jettons (e.g., USDT).               |
| **jettonCollateralMasterAddress**            | `Address`        | Address of the collateral jetton master contract (if collateral is enabled). |
| **royaltyProfitPercentage**               | `Int as uint16`  | Percentage of profit sent to the royalty wallet.                          |

---

## Contract Operation Principle

The Proof of Capital contract is designed to manage the issuance of capital-backed jettons, with transparent conditions for emission and buyback.

### Contract Functions

1. **Deployment and Initial Setup:**
   - After deploying the contract, the creator replenishes it with jettons and sets a lock for **six months** or **10 minutes** (for initial contract testing).
   - The creator can extend the **lock** for an additional period: **six months** or **10 minutes**.

2. **Interacting with the Contract:**
   - **Market Maker:**
     - During the lock period and when the "unlock window" is not active, only the market maker can exchange tokens with the contract.
     - They have the right to buy and sell jettons, aligning the contract's price with prices in DEX pools.
   - **Other Users:**
     - **Two months before the lock ends,** everyone can interact with the contract.
     - Before this point, interaction with the contract is possible during special periods called **"unlock windows."**
     - During the "unlock window" and two months before the lock ends, anyone can return the jettons they purchased from the contract in exchange for collateral.
   - **Return Wallet:**
     - A special wallet from which tokens are returned to the contract, releasing collateral from lower levels.
     - This is an alternative to the burning procedure to use the earned tokens in the future as capitalization grows.

3. **Completion of Lock:**
   - After the lock ends, the creator can withdraw all coins and all collateral from the contract.

### Important Notes

- **Use Getter Functions:**
  - When working with the contract, always use getter functions to check the results of your operations **before** executing them.
  - This will help avoid unexpected results.

- **Interacting with the Contract:**
  - Never send coins (jettons) directly from your wallet to the contract.
    - If you send jettons without calling the appropriate functions, the contract may not process the transaction, and your coins may be lost.
  - If you send TON directly (provided collateral is in TON):
    - The contract may reject the operation if more than two months remain until the lock ends or if collateralization in another coin is enabled.
    - The contract may send you coins (jettons) if less than two months remain until the lock ends or if a special "unlock window" is active.
    - Always check the results of getter functions before interacting with the contract. If the contract does not have enough jettons, it will send all that remains. If no coins are left, the TON will simply go to the contract's balance.
  - Similar rules apply for collateral in another coin; however, such interaction is carried out not directly but through special software tools.

- **Profit and Fees:**
  - The contract supports **dynamic configuration of profit distribution** between the owner (as a fund for development and marketing) and the royalty wallet, including the ability to switch profit withdrawal mode—immediately or upon request.
  - The **Royalty** wallet is specified on the website [proofofcapital.org](https://proofofcapital.org).

---

## Calling Getter Functions

To obtain data about the current state of the contract and the results of internal functions, you can use getter functions:

1. Go to **TON Viewer** or a similar tool.
2. Open the **Methods** tab.
3. In the **Arbitrary method** field, enter the name of the getter function.
4. If necessary, add arguments.
5. Click the **Execute** button to perform the request.

**We recommend** always using getter functions before performing operations to verify the expected results.

---

## Contact Information

For any questions, please contact us using the details provided on the website [proofofcapital.org](https://proofofcapital.org).

In early February, we passed a second audit, which was published in the previous version of the contract. An example of a working contract based on the second version is available [here](https://tonviewer.com/EQBGN2w9fUVNfJ0IBKDQ2vVy6S_lDug4q1UYdRhkFA-r_POK).

Now we have released the third version of the contract (current), taking into account all the wishes of users and clients, and have also successfully passed a third audit, which will be published for the current version of the contract.

Follow important news and updates on our Telegram channel: [@pocorg](https://t.me/pocorg).