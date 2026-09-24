// Proof of Capital is a technology for managing the issue of tokens that are backed by capital.
// The contract allows you to block the desired part of the issue for a selected period with a
// guaranteed buyback under pre-set conditions.

// During the lock-up period, only the market maker appointed by the contract creator has the
// right to buyback the tokens. Starting two months before the lock-up ends, any token holders
// can interact with the contract. They have the right to return their purchased tokens to the
// contract in exchange for the collateral.

// The goal of our technology is to create a market for assets backed by capital and
// transparent issuance management conditions.

// You can integrate the provided contract and Proof of Capital technology into your token if
// you specify the royalty wallet address of our project, listed on our website:
// https://proofofcapital.org

// All royalties collected are automatically used to repurchase the project's core token, as
// specified on the website, and are returned to the contract.

// This is the third version of the contract. It introduces the following features: the ability to choose any jetton as collateral, build collateral with an offset,
// perform delayed withdrawals (and restrict them if needed), assign multiple market makers, modify royalty conditions, and withdraw profit on request.


import "@stdlib/deploy";
import "@stdlib/ownable";
import "./messages";

const TEN_MINUTES: Int = 600; // 10 minutes (used for lock extension in tests)
const MIN_CONTROL_PERIOD: Int = 21_600; // 6 hours (minimum duration of the "unlock window" — the period when the contract is open to all)
const RETURN_WALLET_CHANGE_DELAY: Int = 86_400; // 24 hours delay for return wallet change proposal confirmation

const SEVEN_DAYS: Int = 604_800; // 7 days (used as the period for migration)
const THIRTY_DAYS: Int = 2_592_000; // 30 days before the migration dates for the primary and backing tokens
const OLD_CONTRACT_UPDATE_PERIOD: Int = 3_456_000; // 40 days minimum period between old contract address updates
const SIXTY_DAYS: Int = 5_184_000; // Starting 60 days before the lock-up ends, any token holders can interact with the contract.
const NINETY_DAYS: Int = 7_776_000; // 90 days (used for lock extension)
const ONE_HUNDRED_EIGHTY_TWO_DAYS: Int = 15_724_800; // 182 days (used for lock extension)
const ONE_THOUSAND_EIGHT_HUNDRED_TWENTY_FIVE_DAYS: Int = 157_680_000; // 1825 days (used as the maximum lock extension period)
const FIVE_HUNDREDTHS_TON: Int = ton("0.05"); // minimum TON amount for covering fees
const COMMISSION_MULTIPLIER: Int = 10; // commission multiplier (used to calculate the remaining contract balance when withdrawing TON equal to 10 times the fee)

const MAX_PERCENT: Int = 1000; // Maximum percentage value
const FIXED_ROYALTY_PROFIT_PERCENT: Int = 200; // Fixed 20% royalty share

// Limits the given period to a range between MIN_CONTROL_PERIOD and THIRTY_DAYS.
inline fun getPeriod(period: Int): Int {
    if (period < MIN_CONTROL_PERIOD) {
        period = MIN_CONTROL_PERIOD;
    } else if (period > THIRTY_DAYS) {
        period = THIRTY_DAYS;
    }
    return period;
}

contract ProofOfCapital with Deployable, Ownable {
    isActive: Bool = true; // Contract activity flag
    oldContractAddress: Address; // Address of the old contract, from which coins are expected to be transferred to the current contract (messages are treated as if sent by the owner)
    oldContractAddressesMap: map<Address, Bool>; // Map of old contracts addresses
    oldContractAddressesLength: Int as uint8; // Number of old contracts in the map
    lastOldContractAddressChangeTime: Int as uint64 = 0; // Time of the last old contract address change

    id: Int as uint256; // Unique contract identifier, passed during deployment and used to initialize the contract address when choosing a special address (default is 0)
    owner: Address; // Creator's address — the main owner of the contract, who can manage it and perform certain actions (token deposits, withdrawals, setting locks, changing participants)
    reserveOwner: Address; // Backup owner's address, who can replace the creator (in case access to the main owner is lost) and replace themselves
    launchJettonMasterAddress: Address; // Address of the jetton master contract, used to obtain the wallet address of the launch jetton
    returnWalletAddress: Address; // Return wallet address, which can return tokens to the contract and receive collateral from lower levels
    royaltyWalletAddress: Address; // Royalty wallet address, which receives royalties from revenue-generating operations
    lockEndTime: Int as uint64; // UNIX time until which certain actions are blocked (token withdrawals, purchases, sales by regular users, etc.)
    initialPricePerToken: Int as coins; // Initial price of a single jetton
    firstLevelJettonQuantity: Int as coins; // Number of tokens at the first level (before the first price increase)
    priceIncrementMultiplier: Int as uint16; // Price increase multiplier when moving to a new level
    commission: Int as coins; // Fee charged on transactions (in TON)
    controlDay: Int as uint64; // Date of the "unlock window", which opens every 30 days by default for regular user trading
    controlPeriod: Int as uint32; // Duration of the "unlock window"

    levelIncreaseMultiplier: Int as int16; // Multiplier for increasing the number of tokens at the next level before the trend change
    trendChangeStep: Int as uint8; // Step at which the trend changes — after this step, the number of issued tokens starts to decrease
    levelDecreaseMultiplierAfterTrend: Int as int16; // Multiplier for decreasing the number of tokens per level after the trend change
    profitPercentage: Int as uint16; // Profit percentage to be distributed between the owner and the royalty wallet
    totalJettonsSold: Int as coins; // Total number of jettons sold
    contractCollateralBalance: Int as coins; // Balance of collateral jettons
    contractJettonBalance: Int as coins; // Balance of the contract's launch jetton
    jettonsEarned: Int as coins; // Number of earned jettons — these are the jettons returned to the contract from the returnWalletAddress
    quantityJettonsPerLevel: Int as coins; // Number of jettons at the current level
    actualProfit: Int as coins; // Actual profit to be distributed between the owner and the royalty wallet
    currentPrice: Int as coins; // Current price of the jetton
    currentStep: Int as coins; // Current step the contract is on
    remainderOfStep: Int as coins; // Remaining jettons at the current step

    // Variables for tracking earned jettons
    currentStepEarned: Int as coins; // Current return step the contract is on
    remainderOfStepEarned: Int as coins; // Remaining jettons at the current return step
    quantityJettonsPerLevelEarned: Int as coins; // Number of jettons at the current return level
    currentPriceEarned: Int as coins; // Current price of the return jetton

    contractLaunchJettonWalletAddress: Address; // Wallet address of the contract's launch jetton
    // Variables for withdrawing third-party jettons that may accidentally be sent to the contract
    additionalJettonWalletAddress: Address; // Wallet address of the contract's additional jetton

    // Variables for offset accounting. Used to launch the contract when some jettons are missing at deployment.
    offsetJettons: Int as coins; // Offset in jettons, used for calculating the offset
    offsetStep: Int as coins; // Current offset step
    offsetPrice: Int as coins; // Price at the current offset step
    remainderOffsetJettons: Int as coins; // Remaining jettons at the current offset step
    sizeOffsetStep: Int as coins; // Current size of the offset step

    isFirstPurchase: Bool; // Flag indicating if this is the first purchase (true – first deposit, false – all subsequent ones)

    // New collateral
    jettonCollateral: Bool; // Jetton collateral flag. If False — collateral is provided in TON.
    jettonCollateralMasterAddress: Address; // Master contract address of the collateral jetton
    contractJettonCollateralWalletAddress: Address; // Contract's collateral jetton wallet address

    // Storage of additional market maker addresses
    marketMakerAddressesMap: map<Address, Bool>; // Map of market maker addresses
    marketMakerAddressesLength: Int as uint8; // Number of market makers in the map

    // Profit withdrawal
    ownerTonBalance: Int as coins; // Owner's profit in TON
    royaltyTonBalance: Int as coins; // Royalty profit in TON
    ownerCollateralBalance: Int as coins; // Owner's profit in collateral jettons
    royaltyCollateralBalance: Int as coins; // Royalty profit in collateral jettons
    profitInTime: Bool; // Flag indicating whether profit is withdrawn immediately or upon request (true – on request, false – immediately)
    royaltyProfitPercent: Int as uint16; // Royalty profit percentage (from 1 (0.1 %) to MAX_PERCENT (100 %))
    creatorProfitPercent: Int as uint16; // Owner profit percentage (from 1 (0.1 %) to MAX_PERCENT (100 %))
    profitBeforeTrendChange: Int as uint16; // Profit percentage before trend change (from 1 (0.1 %) to MAX_PERCENT (100 %))

    canWithdrawal: Bool = true; // Flag indicating whether early delayed withdrawal is allowed (true – allowed, false – prohibited)

    // Migration
    launchJettonMigrationDate: Int as uint64 = 0; // End date of migration for the launch jetton
    launchJettonMigrationAmount: Int as coins = 0; // Amount of the launch jetton for migration
    recipientMigrationLaunchJetton: Address; // Recipient address for the migration of the launch jetton

    collateralJettonMigrationDate: Int as uint64 = 0; // End date of the waiting period for delayed withdrawal of the collateral token
    recipientMigrationCollateralJetton: Address; // Recipient address for the migration of the collateral jetton
    jettonDecimals: Int as uint32; // Number of decimals for the jetton
    dao: Address; // DAO address
    unaccountedCollateralBalance: Int as coins = 0; // Unaccounted collateral balance
    unaccountedOffsetBalance: Int as coins = 0; // Unaccounted offset balance
    unaccountedOffsetJettonBalance: Int as coins = 0; // Unaccounted offset jetton balance for gradual processing
    unaccountedReturnBuybackBalance: Int as coins = 0; // Unaccounted return buyback balance for gradual processing

    // Return wallet change proposal
    proposedReturnWalletAddress: Address? = null; // Proposed return wallet address
    proposedReturnWalletChangeTime: Int as uint64 = 0; // Time when return wallet change was proposed

    isInitialized: Bool = false; // Flag indicating whether the contract's jetton wallets are initialized (required to run self.calculateOffset())

    init(id: Int,
        owner: Address,
        marketMakerAddress: Address,
        launchJettonMasterAddress: Address,
        returnWalletAddress: Address,
        royaltyWalletAddress: Address,
        lockEndTime: Int,
        initialPricePerToken: Int,
        firstLevelJettonQuantity: Int,
        priceIncrementMultiplier: Int,
        levelIncreaseMultiplier: Int,
        trendChangeStep: Int,
        levelDecreaseMultiplierAfterTrend: Int,
        profitPercentage: Int,
        offsetJettons: Int,
        controlPeriod: Int,
        jettonCollateral: Bool,
        jettonCollateralMasterAddress: Address,
        royaltyProfitPercent: Int,
        profitBeforeTrendChange: Int,
        jettonDecimals: Int
        ) {
        self.oldContractAddress = owner;
        self.oldContractAddressesMap = emptyMap();
        self.oldContractAddressesLength = 0;

        self.id = id;
        self.owner = owner;
        self.launchJettonMasterAddress = launchJettonMasterAddress;
        self.contractLaunchJettonWalletAddress = owner;
        self.returnWalletAddress = returnWalletAddress;
        self.royaltyWalletAddress = royaltyWalletAddress;
        self.lockEndTime = lockEndTime;
        self.initialPricePerToken = initialPricePerToken;
        self.firstLevelJettonQuantity = firstLevelJettonQuantity;
        self.priceIncrementMultiplier = priceIncrementMultiplier;
        self.levelIncreaseMultiplier = levelIncreaseMultiplier;
        self.trendChangeStep = trendChangeStep;
        self.levelDecreaseMultiplierAfterTrend = levelDecreaseMultiplierAfterTrend;
        self.profitPercentage = profitPercentage;
        self.profitBeforeTrendChange = profitBeforeTrendChange;
        self.jettonCollateral = jettonCollateral;
        self.jettonCollateralMasterAddress = jettonCollateralMasterAddress;
        self.contractJettonCollateralWalletAddress = owner;
        self.jettonDecimals = jettonDecimals;
        self.currentStep = 0;
        self.remainderOfStep = firstLevelJettonQuantity;
        self.contractJettonBalance = 0;
        self.jettonsEarned = 0;
        self.contractCollateralBalance = 0;
        self.additionalJettonWalletAddress = owner;
        self.totalJettonsSold = 0;
        self.quantityJettonsPerLevel = firstLevelJettonQuantity;
        self.actualProfit = 0;
        self.currentPrice = initialPricePerToken;
        self.currentStepEarned = 0;
        self.remainderOfStepEarned = firstLevelJettonQuantity;
        self.quantityJettonsPerLevelEarned = firstLevelJettonQuantity;
        self.currentPriceEarned = initialPricePerToken;
        self.commission = FIVE_HUNDREDTHS_TON;
        self.controlDay = now() + THIRTY_DAYS;

        self.offsetJettons = offsetJettons;
        self.offsetStep = 0;
        self.offsetPrice = initialPricePerToken;
        self.remainderOffsetJettons = firstLevelJettonQuantity;
        self.sizeOffsetStep = firstLevelJettonQuantity;
        self.controlPeriod = getPeriod(controlPeriod);
        self.isFirstPurchase = true;

        self.reserveOwner = owner;

        self.marketMakerAddressesMap = emptyMap();
        self.marketMakerAddressesLength = 1;
        self.marketMakerAddressesMap.set(marketMakerAddress, true);

        self.ownerTonBalance = 0;
        self.royaltyTonBalance = 0;
        self.ownerCollateralBalance = 0;
        self.royaltyCollateralBalance = 0;
        self.profitInTime = true;

        self.royaltyProfitPercent = FIXED_ROYALTY_PROFIT_PERCENT;
        self.creatorProfitPercent = MAX_PERCENT - FIXED_ROYALTY_PROFIT_PERCENT;

        self.recipientMigrationLaunchJetton = owner;
        self.recipientMigrationCollateralJetton = owner;

        self.dao = owner;

        require(self.initialPricePerToken > 0, "Initial price must be positive");
        require(self.levelDecreaseMultiplierAfterTrend < MAX_PERCENT, "Multiplier too high");
        require(self.levelDecreaseMultiplierAfterTrend > -MAX_PERCENT, "Multiplier too low");
        require(self.levelIncreaseMultiplier < MAX_PERCENT, "Multiplier too high");
        require(self.levelIncreaseMultiplier > -MAX_PERCENT, "Multiplier too low");
        require(self.priceIncrementMultiplier > 0, "Price increment too low");
        require(self.priceIncrementMultiplier <= MAX_PERCENT, "Price increment too high");
        require(self.royaltyProfitPercent > 9 && self.royaltyProfitPercent <= MAX_PERCENT, "Started royalty profit cannot be less than ten and greater than thousand");

        message(MessageParameters{
            to: self.launchJettonMasterAddress,
            value: 0,
            mode: SendRemainingValue,
            bounce: false,
            body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: false}.toCell()
        });
    }

    // Receives and sends messages to jetton master contracts, stores the addresses of the launch and collateral jetton wallets.
    // Change flag isInitialized after all jetton wallets received.
    // Sets unaccounted offset balance instead of immediately calculating offset.
    receive(msg: TakeWalletAddress) {
        // TODO: store the LP wallet address in addition to the launch and collateral wallets.
    }

    // Extends the lock to a specific timestamp at the request of the owner.
    receive(msg: ExtendLock) {
        require(sender() == self.owner, "Access is only for the owner");
        require(context().value >= self.commission, "Amount must be greater than commission");
        require(msg.lockTimestamp > now(), "Invalid time period");
        require(msg.lockTimestamp > self.lockEndTime, "New lock must be greater than old");
        require(msg.lockTimestamp <= now() + ONE_THOUSAND_EIGHT_HUNDRED_TWENTY_FIVE_DAYS, "Lock cannot exceed five years");
        self.lockEndTime = msg.lockTimestamp;
        let notification: StringBuilder = beginString();
        notification.append("Lock extended until ");
        notification.append(msg.lockTimestamp.toString());
        self.notify(notification.toString().asComment());
    }

    // Locks the ability of the owner to withdraw funds if they want to waive this right during the lock period.
    // If this receiver is called when less than 60 days remain until the end of the lock (i.e., when users can already interact with the contract),
    // the owner can re-enable withdrawal—for example, to transfer jettons to another contract with a lock (for a safe migration).
    receive(msg: BlockMigration) {
        // TODO: replace migration with the dedicated Migration contract flow.
    }


    // Schedules a migration of the launch jetton in 30 days to the specified address.
    receive(msg: JettonMigration) {
        // TODO: replace migration with the dedicated Migration contract flow.
    }

    // Cancels the delayed withdrawal of the launch jetton and resets the associated data. It can be used by the creator, the royalty wallet, or the dao.
    receive(msg: StopJettonMigration) {
        // TODO: replace migration with the dedicated Migration contract flow.
    }

    // Confirms and executes the migration of launch jettons after the waiting period expires.
    receive(msg: ConfirmJettonMigration) {
        // TODO: replace migration with the dedicated Migration contract flow.
    }

    // Schedules a migration of the collateral jettons in 30 days to the specified address.
    receive(msg: CollateralMigration) {
        // TODO: replace migration with the dedicated Migration contract flow.
    }

    // Cancels the migration of collateral jettons and resets the related data. Can be called by the creator, the royalty wallet, or the dao.
    receive(msg: StopCollateralMigration) {
        // TODO: replace migration with the dedicated Migration contract flow.
    }

    // Confirms and executes the migration of collateral jettons after the waiting period expires.
    receive(msg: ConfirmCollateralMigration) {
        // TODO: replace migration with the dedicated Migration contract flow.
    }

    // Assigns a new main owner. Only the current the reserve owner can perform this action.
    // If the current owner is the the reserve owner, both addresses are updated to the new owner.
    receive(msg: AssignNewOwner) {
        require(context().value >= self.commission, "Insufficient funds to cover commission");
        require(sender() == self.owner || sender() == self.reserveOwner, "Only the owner or the reserve owner can make changes.");
        require(msg.newOwner != newAddress(0, 0), "New owner address cannot be null.");
        require((!self.oldContractAddressesMap.exists(msg.newOwner)), "Old contract address cannot be equal to any of addresses in contract");
        if (self.owner == self.reserveOwner) {
            self.reserveOwner = msg.newOwner;
        }
        if (self.owner == self.dao) {
            self.dao = msg.newOwner;
        }
        self.owner = msg.newOwner;
        self.notify("Owner assigned".asComment());
    }

    // Assigns a new the reserve owner. Only the current the reserve owner can perform this action.
    receive(msg: AssignNewReserveOwner) {
        require(context().value >= self.commission, "Insufficient funds to cover commission");
        require(sender() == self.reserveOwner, "Only the reserve owner can make changes.");
        require(msg.reserveOwner != newAddress(0, 0), "New the reserve owner address cannot be null.");
        self.reserveOwner = msg.reserveOwner;
        self.notify("Reserve owner assigned".asComment());
    }

    // Changes the commission value.
    receive(msg: ChangeCommissionValue) {
        // TODO: replace the absolute commission value with a configurable global coefficient.
    }

    // Updates the royalty wallet address. Access is allowed only for the current royalty address.
    receive(msg: ChangeRoyaltyWallet) {
        require(context().value >= self.commission, "Insufficient funds to cover commission");
        require(sender() == self.royaltyWalletAddress, "Access is only for royalty.");
        require(msg.newRoyaltyWalletAddress != newAddress(0, 0), "New royalty wallet address cannot be null");
        self.royaltyWalletAddress = msg.newRoyaltyWalletAddress;
        self.notify("Royalty wallet address changed".asComment());
    }

    // Updates the additional jetton addresses and transfers the specified amount to the dao.
    // Verifies the uniqueness and validity of the new addresses.
    // Intended for withdrawing third-party jettons mistakenly sent to the contract.
    receive(msg: AddAdditionalJettonData) {
        require(sender() == self.dao, "Access is only for the dao");
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        require(msg.newAdditionalJettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address in message cannot be zero");
        if (now() < self.lockEndTime) {
            require(msg.newAdditionalJettonWalletAddress != self.contractJettonCollateralWalletAddress, "Additional jetton wallet address in message cannot be collateral jetton wallet");
            require(msg.newAdditionalJettonWalletAddress != self.contractLaunchJettonWalletAddress, "Additional jetton wallet address in message cannot be launch jetton wallet");
        }
        self.additionalJettonWalletAddress = msg.newAdditionalJettonWalletAddress;
        self.transferTokensToWithPayload(self.additionalJettonWalletAddress, self.dao, msg.amount, SendOtherJettonsToDao{}.toCell(), self.commission * 2, self.commission);
    }

    // Adds a new market maker address to the map if it is not already present.
    receive(msg: AddMarketMakerAddresses) {
        // TODO: replace the market-maker map with one configured external market-maker address.
    }

    // Removes a market maker address from the map if it exists.
    receive(msg: DeleteMarketMakerAddresses) {
        // TODO: clear the single configured external market-maker address.
    }

    // Handler for incoming JettonTransferNotification messages.
    //
    // Executes logic based on the notification sender and the contract state.
    //
    // Main scenarios:
    // 1. If the notification comes from the collateral jetton wallet (contractJettonCollateralWalletAddress):
    //    - Ensures collateral mode is active and the sender address is valid.
    //    - If the transfer is from the owner or oldContractAddress:
    //      - If a positive offset in collateral jettons exists, the collateral balance is increased and the collateral jettons are accounted for.
    //    - Otherwise:
    //      - Verifies the sender is an authorized MarketMaker (depending on lock period or unlock window).
    //      - Updates the control day if needed.
    //      - Checks fee payment and sufficient collateral jetton balance.
    //      - Calculates the number of launch jettons to issue, distributes profit to creator and royalty.
    //      - Updates the collateral balance and total sold jettons.
    //      - Sends launch jettons to the sender.
    //      - Updates the total collateral jetton amount.
    //
    // 2. If the notification comes from the launch jetton wallet (contractLaunchJettonWalletAddress):
    //    - Ensures consistency of jetton states (earned and offset).
    //    - If the transfer is from the owner or oldContractAddress:
    //      - Depending on the internal counter, updates the launch jetton balance or triggers offset recalculation.
    //    - If the transfer is from returnWalletAddress (buyback):
    //      - Checks commission sufficiency.
    //      - Calculates the collateral amount to be paid based on the amount of jettons being bought back and current offset.
    //      - Updates collateral and launch jetton balances.
    //      - If required, sends funds to the owner's address (via TON or jetton transfer).
    //    - Otherwise:
    //      - Checks MarketMaker permissions or unlock window conditions.
    //      - Verifies sufficient funds for jetton buyback.
    //      - Calculates the amount of collateral jettons to return and updates collateral and sold jetton balances.
    //      - Sends funds back to the user (via TON or jetton, depending on the collateral mode).
    //      - Updates the total amount of collateral jettons.
    //
    // Always checks that the contract is active and initialized, otherwise throws an error.
    // If any error occurs (while the contract is active and initialized), the transferred jettons are refunded to the sender with a specified reason.
    receive(msg: JettonTransferNotification) {
        // TODO: dispatch the payload opcode to dedicated notification sub-handlers.
    }
        

    // You can use DAO for launch and manage your contract. Read more about this on https://tokens.family
    receive(msg: SetDao) {
        require(sender() == self.dao, "Access is only for the dao");
        self.dao = msg.dao;
    }

    // Transfers all unsold jettons to the owner after the lock period ends.
    // Verifies caller's permission and lock time.
    // Resets the contract state to initial parameters.
    receive(msg: WithdrawAllCoins) {
        // TODO: after successful migration, send every launch token to the migration target.
    }

    // Transfers the entire collateral jetton balance to the owner after the lock period ends.
    // Verifies caller's permission, lock time, and collateral mode.
    // Resets the collateral balance after the transfer.
    receive(msg: WithdrawAllCollateralCoins) {
        // TODO: after successful migration, send every collateral token to the migration target.
    }

    // Transfers the entire available TON balance to the owner after the lock period ends.
    // Verifies caller's permission and lock time.
    // Resets the collateral balance and updates the TON balance used for fees.
    receive(msg: WithdrawAllTons) {
        // TODO: after successful migration, send every TON coin to the migration target.
    }

    // Sends unused TON to the dao.
    // Takes into account the collateral mode and deducts the fee.
    receive(msg: WithdrawUnusedTons) {
        // TODO: after successful migration, send every unused TON coin to the migration target.
    }

    // Sends profit to the current owner or the royalty wallet depending on the requester's rights.
    receive(msg: GetProfitOnRequest) {
        // TODO: a request from either owner or royalty must pay both parties immediately.
    }

    // Sends the current price of the launch jetton to the sender.
    receive(msg: FetchCurrentPrice) {
        require(context().value >= self.commission, "Insufficient funds to cover commission for price");
        self.notify(GetCurrentPrice{ queryId: msg.queryId, originalGasTo: msg.originalGasTo, currentPrice: self.currentPrice }.toCell());
    }
    // jetton collateral, launch token, active, current price
    receive(msg: FetchContractInfoAfterUpdatePoc) {
        require(context().value >= self.commission, "Insufficient funds to cover commission for transfer jetton collateral");
        self.notify(GetContractInfoAfterUpdatePoc{ queryId: msg.queryId, originalGasTo: msg.originalGasTo, jettonCollateralAddress: self.jettonCollateralMasterAddress, jettonLaunchAddress: self.launchJettonMasterAddress, isActive: self.isActive, currentPrice: self.currentPrice, lockDate: self.lockEndTime }.toCell());
    }

    // Helper function to check if the caller is allowed to trade at the current moment.
    fun checkTradingAccess(): Bool {
        // TODO: implement trading access rules for the reduced contract.
    }

    // Sends the specified amount of jettons with a comment to the given address.
    fun transferTokensToWithPayload(toAddress: Address, recipient: Address, amount: Int, payload: Cell, value: Int, forwardTonAmount: Int) {
        let forwardPayload = beginCell().storeBit(false).storeSlice(payload.asSlice()).asSlice();
        message(MessageParameters{
            to: toAddress,
            value: value,
            body: JettonTransfer{
                queryId: now(),
                amount: amount,
                destination: recipient,
                responseDestination: recipient,
                customPayload: null,
                forwardTonAmount: forwardTonAmount,
                forwardPayload: forwardPayload,
            }.toCell(),
        });
    }

    // Returns the profit percentage depending on the current step and the trend change step.
    fun calculateProfit(currentStep: Int): Int {
        // TODO: use 0.5% for the external MM and 5% for other participants; add configurable limits (external 0.5%-10%, MM minimum 0%).
    }

}
