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

const SEVEN_DAYS: Int = 604_000; // 7 days (used as the period for deferred withdrawal)
const THIRTY_DAYS: Int = 2_592_000; // 30 days before the deferred withdrawal dates for the primary and backing tokens
const SIXTY_DAYS: Int = 5_184_000; // Starting 60 days before the lock-up ends, any token holders can interact with the contract.
const THREE_MONTHS: Int = 7_776_000; // 3 months (used for lock extension)
const HALF_YEAR: Int = 15_768_000; // half a year (used for lock extension)
const TWO_YEARS: Int = 63_072_000; // 2 years (used as the maximum lock extension period)
const SIX_HUNDREDTHS_TON: Int = ton("0.06"); // minimum TON amount for covering fees
const COMMISSION_MULTIPLIER: Int = 10; // commission multiplier (used to calculate the remaining contract balance when withdrawing TON equal to 10 times the fee)

const MAX_PERCENT: Int = 1000; // Maximum percentage value

// Limits the given period to a range between MIN_CONTROL_PERIOD and THIRTY_DAYS.
fun getPeriod(period: Int): Int {
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
    oldContractAddressesMap: map<Address, Int as uint8>; // Map of old contracts addresses
    oldContractAddressesLength: Int as uint8; // Number of old contracts in the map

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
    levelDecreaseMultiplierafterTrend: Int as int16; // Multiplier for decreasing the number of tokens per level after the trend change
    profitPercentage: Int as uint16; // Profit percentage to be distributed between the owner and the royalty wallet
    queryId: Int as uint64; // Identifier of the last transaction
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

    callJettonsID: Int as uint8; // Call counter for the initial deposit (1 – first deposit, 0 – all subsequent ones)

    // New collateral
    jettonCollateral: Bool; // Jetton collateral flag. If False — collateral is provided in TON.
    jettonCollateralMasterAddress: Address; // Master contract address of the collateral jetton
    contractJettonCollateralWalletAddress: Address; // Contract's collateral jetton wallet address

    // Storage of additional market maker addresses
    marketMakerAddressesMap: map<Address, Int as uint8>; // Map of market maker addresses
    marketMakerAddressesLength: Int as uint8; // Number of market makers in the map

    // Profit withdrawal
    ownerTonBalance: Int as coins; // Owner's profit in TON
    royaltyTonBalance: Int as coins; // Royalty profit in TON
    ownerCollateralBalance: Int as coins; // Owner's profit in collateral jettons
    royaltyCollateralBalance: Int as coins; // Royalty profit in collateral jettons
    profitInTime: Bool; // Flag indicating whether profit is withdrawn immediately or upon request (true – on request, false – immediately)
    royaltyProfitPercent: Int as uint16; // Royalty profit percentage (from 1 (0.1 %) to MAX_PERCENT (100 %))
    creatorProfitPercent: Int as uint16; // Owner profit percentage (from 1 (0.1 %) to MAX_PERCENT (100 %))
    coefficientProfit: Int as uint16; // Coefficient for calculating the profit percentage (from 1 (100 %) to MAX_PERCENT (10000 %))

    canWithdrawal: Bool = true; // Flag indicating whether early delayed withdrawal is allowed (true – allowed, false – prohibited)

    // Deferred withdrawal
    launchJettonDeferredWithdrawalDate: Int as uint64 = 0; // End date of deferred withdrawal for the launch jetton
    launchJettonDeferredWithdrawalAmount: Int as coins = 0; // Amount of the launch jetton for deferred withdrawal
    recipientDeferredWithdrawalLaunchJetton: Address; // Recipient address for the deferred withdrawal of the launch jetton

    collateralJettonDeferredWithdrawalDate: Int as uint64 = 0; // End date of the waiting period for delayed withdrawal of the collateral token
    recipientDeferredWithdrawalCollateralJetton: Address; // Recipient address for the deferred withdrawal of the collateral jetton
    jettonDecimals: Int as uint32; // Number of decimals for the jetton
    farm: Address; // Farm address

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
        levelDecreaseMultiplierafterTrend: Int,
        profitPercentage: Int,
        offsetJettons: Int,
        controlPeriod: Int,
        jettonCollateral: Bool,
        jettonCollateralMasterAddress: Address,
        royaltyProfitPercent: Int,
        coefficientProfit: Int,
        jettonDecimals: Int
        ) {
        self.oldContractAddress = owner;
        self.oldContractAddressesMap = emptyMap();
        self.oldContractAddressesLength = 0;

        self.id = 0;
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
        self.levelDecreaseMultiplierafterTrend = levelDecreaseMultiplierafterTrend;
        self.profitPercentage = profitPercentage;
        self.coefficientProfit = coefficientProfit;
        self.jettonCollateral = jettonCollateral;
        self.jettonCollateralMasterAddress = jettonCollateralMasterAddress;
        self.contractJettonCollateralWalletAddress = owner;
        self.jettonDecimals = jettonDecimals;
        self.currentStep = 0;
        self.remainderOfStep = firstLevelJettonQuantity;
        self.contractJettonBalance = 0;
        self.jettonsEarned = 0;
        self.queryId = 0;
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
        self.commission = SIX_HUNDREDTHS_TON;
        self.controlDay = now() + THIRTY_DAYS;

        self.offsetJettons = offsetJettons;
        self.offsetStep = 0;
        self.offsetPrice = initialPricePerToken;
        self.remainderOffsetJettons = firstLevelJettonQuantity;
        self.sizeOffsetStep = firstLevelJettonQuantity;
        self.controlPeriod = getPeriod(controlPeriod);
        self.callJettonsID = 1;

        self.reserveOwner = owner;

        self.marketMakerAddressesMap = emptyMap();
        self.marketMakerAddressesLength = 1;
        self.marketMakerAddressesMap.set(marketMakerAddress, self.marketMakerAddressesLength);

        self.ownerTonBalance = 0;
        self.royaltyTonBalance = 0;
        self.ownerCollateralBalance = 0;
        self.royaltyCollateralBalance = 0;
        self.profitInTime = true;

        self.royaltyProfitPercent = royaltyProfitPercent;
        self.creatorProfitPercent = MAX_PERCENT - royaltyProfitPercent;

        self.recipientDeferredWithdrawalLaunchJetton = owner;
        self.recipientDeferredWithdrawalCollateralJetton = owner;

        self.farm = owner;

        require(self.initialPricePerToken > 0, "Initial price must be positive");
        require(self.levelDecreaseMultiplierafterTrend < MAX_PERCENT, "Multiplier too high");
        require(self.levelDecreaseMultiplierafterTrend > -MAX_PERCENT, "Multiplier too low");
        require(self.levelIncreaseMultiplier < MAX_PERCENT, "Multiplier too low");
        require(self.levelIncreaseMultiplier > -MAX_PERCENT, "Multiplier too high");
        require(self.priceIncrementMultiplier > 0, "Price increment too low");
        require(self.priceIncrementMultiplier <= MAX_PERCENT, "Price increment too high");
        require(self.royaltyProfitPercent > 9 && self.royaltyProfitPercent <= MAX_PERCENT, "Started royalty profit cannot be less than ten and greater than thousand");

        message(MessageParameters{
            to: self.launchJettonMasterAddress,
            value: 0,
            mode: SendRemainingValue,
            body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: false}.toCell()
        });
    }

    // Receives and sends messages to jetton master contracts, stores the addresses of the launch and collateral jetton wallets.
    // Change flag isInitialized after all jetton wallets received.
    // Triggers the offset calculation function.
    receive(msg: TakeWalletAddress) {
        require(sender() == self.launchJettonMasterAddress || sender() == self.jettonCollateralMasterAddress, "Invalid lounch or collateral jetton master sender");
        require(!self.isInitialized, "Contract jetton wallets are already initialized");
        if (sender() == self.launchJettonMasterAddress) {
            self.contractLaunchJettonWalletAddress = msg.wallet_address;
            if (self.jettonCollateral) {
                message(MessageParameters{
                    to: self.jettonCollateralMasterAddress,
                    value: 0,
                    mode: SendRemainingValue,
                    body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: true}.toCell()
                });
            } else {
                self.calculateOffset(self.offsetJettons);
                self.isInitialized = true;
            }
        } else {
            self.contractJettonCollateralWalletAddress = msg.wallet_address;
        }
        if (self.contractLaunchJettonWalletAddress != self.owner && self.contractJettonCollateralWalletAddress != self.owner) {
            self.calculateOffset(self.offsetJettons);
            self.isInitialized = true;
        }
    }

    // Extends the lock for a specified period at the request of the owner. Supported durations are 10 minutes, 3 months, or 6 months.
    receive(msg: ExtendLock) {
        require(sender() == self.owner, "Access is only for the owner");
        require(context().value >= self.commission, "Amount must be greater than commission");
        require(((self.lockEndTime + msg.additionalTime) - now()) < TWO_YEARS, "Lock end time cannot exceed two years");
        require(msg.additionalTime == HALF_YEAR || msg.additionalTime == TEN_MINUTES || msg.additionalTime == THREE_MONTHS, "Invalid time!");
        self.lockEndTime += msg.additionalTime;
        if (msg.additionalTime == HALF_YEAR) {
            message(MessageParameters{
                to: self.owner,
                value: 0,
                bounce: true,
                mode: SendPayFwdFeesSeparately,
                body: "Lock extended for 182 days.".asComment()
            });
        } else if (msg.additionalTime == TEN_MINUTES) {
            message(MessageParameters{
                to: self.owner,
                value: 0,
                bounce: true,
                mode: SendPayFwdFeesSeparately,
                body: "Lock extended for 10 minutes.".asComment()
            });
        } else {
            message(MessageParameters{
                to: self.owner,
                value: 0,
                bounce: true,
                mode: SendPayFwdFeesSeparately,
                body: "Lock extended for 3 months.".asComment()
            });
        }
    }

    // Locks the ability of the owner to withdraw funds if they want to waive this right during the lock period.
    // If this receiver is called when less than 60 days remain until the end of the lock (i.e., when users can already interact with the contract),
    // the owner can re-enable withdrawal—for example, to transfer jettons to another contract with a lock (for a safe migration).
    receive(msg: BlockDeferredWithdrawal) {
        require(sender() == self.owner, "Access is only for the owner");
        if (self.canWithdrawal) {
            self.canWithdrawal = false;
        } else {
            require(self.lockEndTime - now() < SIXTY_DAYS, "Withdrawal is blocked. You can activate Withdrawal later than 60 days before lockEndTime");
            self.canWithdrawal = true;
        }
    }


    // Schedules a deferred withdrawal of the launch jetton in 30 days to the specified address.
    receive(msg: JettonDeferredWithdrawal) {
        require(sender() == self.owner, "Access is only for the owner");
        require(msg.amount > 0 && msg.recipientAddress != newAddress(0, 0), "Recipient address and jetton amount cannot be zero");
        require(self.canWithdrawal, "Deferred withdrawal is blocked");
        require(self.launchJettonDeferredWithdrawalAmount == 0, "Launch jetton deferred withdrawal is already scheduled");
        self.recipientDeferredWithdrawalLaunchJetton = msg.recipientAddress;
        self.launchJettonDeferredWithdrawalDate = now() + THIRTY_DAYS;
        self.launchJettonDeferredWithdrawalAmount = msg.amount;
        message(MessageParameters{
            to: msg.recipientAddress,
            value: self.commission,
            bounce: true,
            mode: SendPayFwdFeesSeparately,
            body: "Requested withdrawal of launch jettons to recipient of current transaction after 30 days".asComment()
        });
    }

    // Cancels the delayed withdrawal of the launch jetton and resets the associated data. It can be used by both the creator and the royalty wallet.
    receive(msg: StopJettonDeferredWithdrawal) {
        require(sender() == self.owner || sender() == self.royaltyWalletAddress || sender() == self.farm, "Access is only for the owner or royaltyWallet or farm");
        require(self.launchJettonDeferredWithdrawalDate != 0, "Launch jetton deferred withdrawal date is not set");
        self.launchJettonDeferredWithdrawalDate = 0;
        self.launchJettonDeferredWithdrawalAmount = 0;
        self.recipientDeferredWithdrawalLaunchJetton = self.owner;
        self.notify("Launch jetton deferred withdrawal stopped and date reset".asComment());
    }

    // Confirms and executes the deferred withdrawal of launch jettons after the waiting period expires.
    receive(msg: ConfirmJettonDeferredWithdrawal) {
        require(sender() == self.owner, "Access is only for the owner");
        require(context().value >= self.commission * 20, "Insufficient funds to cover commission for transfer profit");
        require(self.canWithdrawal, "Deferred withdrawal is blocked");
        require(self.launchJettonDeferredWithdrawalDate != 0, "Launch jetton deferred withdrawal date is not set or reset");
        require(now() >= self.launchJettonDeferredWithdrawalDate, "Launch jetton deferred withdrawal date is not arrived yet");
        require(now() <= self.launchJettonDeferredWithdrawalDate + SEVEN_DAYS, "Launch jetton deferred withdrawal period is finished");

        let amount: Int = min(self.launchJettonDeferredWithdrawalAmount, self.contractJettonBalance - self.totalJettonsSold);
        if (amount > 0) {
            self.transferTokensToWithPayload(self.contractLaunchJettonWalletAddress, self.recipientDeferredWithdrawalLaunchJetton, amount, LaunchJettonDeferredWithdrawal{}.toCell(), self.commission * 20, self.commission * 19);
        }
        
        self.contractJettonBalance -= amount;
        self.launchJettonDeferredWithdrawalDate = 0;
        self.launchJettonDeferredWithdrawalAmount = 0;
        self.recipientDeferredWithdrawalLaunchJetton = self.owner;
    }

    // Schedules a deferred withdrawal of the collateral jettons in 30 days to the specified address.
    receive(msg: CollateralDeferredWithdrawal) {
        require(sender() == self.owner, "Access is only for the owner");
        require(self.canWithdrawal, "Deferred withdrawal is blocked");
        require(msg.recipientAddress != newAddress(0, 0), "Recipient address cannot be null");
        require(self.collateralJettonDeferredWithdrawalDate == 0, "Collateral jetton deferred withdrawal is already scheduled");
        self.recipientDeferredWithdrawalCollateralJetton = msg.recipientAddress;
        self.collateralJettonDeferredWithdrawalDate = now() + THIRTY_DAYS;
        message(MessageParameters{
            to: msg.recipientAddress,
            value: self.commission,
            bounce: true,
            mode: SendPayFwdFeesSeparately,
            body: "Requested withdrawal of collateral jettons to recipient of current transaction after 30 days".asComment()
        });
    }

    // Cancels the deferred withdrawal of collateral jettons and resets the related data. Can be called by either the creator or the royalty wallet.
    receive(msg: StopCollateralDeferredWithdrawal) {
        require(sender() == self.owner || sender() == self.royaltyWalletAddress || sender() == self.farm, "Access is only for the owner or royaltyWallet or farm");
        require(self.collateralJettonDeferredWithdrawalDate != 0, "Collateral jetton deferred withdrawal date is not set");
        self.collateralJettonDeferredWithdrawalDate = 0;
        self.recipientDeferredWithdrawalCollateralJetton = self.owner;
        self.notify("Collateral jetton deferred withdrawal stopped and date reset".asComment());
    }

    // Confirms and executes the deferred withdrawal of collateral jettons after the waiting period expires.
    receive(msg: ConfirmCollateralDeferredWithdrawal) {
        require(sender() == self.owner, "Access is only for the owner");
        require(context().value >= self.commission * 20, "Insufficient funds to cover commission for transfer profit");
        require(self.canWithdrawal, "Deferred withdrawal is blocked");
        require(self.collateralJettonDeferredWithdrawalDate != 0, "Collateral jetton deferred withdrawal date is not set or reset");
        require(now() >= self.collateralJettonDeferredWithdrawalDate, "Collateral jetton deferred withdrawal date is not arrived yet");
        require(now() <= self.collateralJettonDeferredWithdrawalDate + SEVEN_DAYS, "Collateral jetton deferred withdrawal period is finished");

        if (self.jettonCollateral) {
            self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, self.recipientDeferredWithdrawalCollateralJetton, self.contractCollateralBalance, CollateralJettonDeferredWithdrawal{}.toCell(), self.commission * 20, self.commission * 19);
        } else {
            message(MessageParameters{
                to: self.recipientDeferredWithdrawalCollateralJetton,
                value: self.contractCollateralBalance,
                bounce: true,
                mode: SendPayFwdFeesSeparately,
                body: "Collateral jetton deferred withdrawal".asComment()
            });
        }

        self.contractCollateralBalance = 0;
        self.collateralJettonDeferredWithdrawalDate = 0;
        self.recipientDeferredWithdrawalCollateralJetton = self.owner;
        self.isActive = false;
    }

    // Assigns a new main owner. Only the current the reserve owner can perform this action.
    // If the current owner is the the reserve owner, both addresses are updated to the new owner.
    receive(msg: AssignNewOwner) {
        require(sender() == self.owner || sender() == self.reserveOwner, "Only the owner or the reserve owner can make changes.");
        require(msg.newOwner != newAddress(0, 0), "New owner address cannot be null.");
        require((!self.oldContractAddressesMap.exists(msg.newOwner)), "Old contract address cannot be equal to any of addresses in contract");
        if (self.owner == self.reserveOwner) {
            self.reserveOwner = msg.newOwner;
        }
        if (self.owner == self.farm) {
            self.farm = msg.newOwner;
        }
        self.owner = msg.newOwner;
    }

    // Assigns a new the reserve owner. Only the current the reserve owner can perform this action.
    receive(msg: AssignNewReserveOwner) {
        require(sender() == self.reserveOwner, "Only the reserve owner can make changes.");
        require(msg.reserveOwner != newAddress(0, 0), "New the reserve owner address cannot be null.");
        self.reserveOwner = msg.reserveOwner;
    }

    // Toggles the profit withdrawal mode between immediate and on request.
    receive(msg: SwitchProfitMode) {
        require(sender() == self.owner, "Access is only for the owner");
        require(msg.flag != self.profitInTime, "Turn on value cannot be equal");
        require(context().value >= self.commission * 2, "Amount must be greater than commission");
        self.profitInTime = msg.flag;
        message(MessageParameters{
            to: self.royaltyWalletAddress,
            value: self.commission,
            bounce: true,
            mode: SendPayFwdFeesSeparately,
            body: "Profit mode switched".asComment()
        });
    }

    // Changes the commission value.
    receive(msg: ChangeCommissionValue) {
        require(sender() == self.owner, "Access is only for the owner");
        require(msg.commissionValue >= FIVE_HUNDREDTHS_TON && msg.commissionValue <= ton("10"), "Amount must be greater than 0.05");
        self.commission = msg.commissionValue;
    }

    // Updates the return wallet address.
    receive(msg: ChangeReturnWallet) {
        require(sender() == self.owner, "Access is only for the owner");
        require(msg.newReturnWalletAddress != newAddress(0, 0), "New return wallet address cannot be null");
        require((!self.oldContractAddressesMap.exists(msg.newReturnWalletAddress)), "Old contract address cannot be equal to any of addresses in contract");
        self.returnWalletAddress = msg.newReturnWalletAddress;
    }

    // Updates the royalty wallet address. Access is allowed only for the current royalty address.
    receive(msg: ChangeRoyaltyWallet) {
        require(sender() == self.royaltyWalletAddress, "Access is only for royalty.");
        require(msg.newRoyaltyWalletAddress != newAddress(0, 0), "New royalty wallet address cannot be null");
        self.royaltyWalletAddress = msg.newRoyaltyWalletAddress;
    }

    // Changes the profit distribution between the owner and the royalty.
    // The owner can only increase the royalty percentage.
    // The royalty address can only decrease the royalty percentage.
    receive(msg: ChangeProfitPercentage) {
        require(sender() == self.owner || sender() == self.royaltyWalletAddress, "Access only for the owner or royalty");
        require((msg.newRoyaltyProfitPercentage > 0 && msg.newRoyaltyProfitPercentage <= MAX_PERCENT), "Incorrect value of the royalty profit");
        if (sender() == self.owner) {
            require(msg.newRoyaltyProfitPercentage > self.royaltyProfitPercent, "New percentage cannot be less than current");
            self.royaltyProfitPercent = msg.newRoyaltyProfitPercentage;
            self.creatorProfitPercent = MAX_PERCENT - msg.newRoyaltyProfitPercentage;
        } else {
            require(msg.newRoyaltyProfitPercentage < self.royaltyProfitPercent, "New percentage cannot be more than current");
            self.royaltyProfitPercent = msg.newRoyaltyProfitPercentage;
            self.creatorProfitPercent = MAX_PERCENT - msg.newRoyaltyProfitPercentage;
        }
    }

    // Updates the additional jetton addresses and transfers the specified amount to the owner.
    // Verifies the uniqueness and validity of the new addresses.
    // Intended for withdrawing third-party jettons mistakenly sent to the contract.
    receive(msg: AddAdditionalJettonData) {
        require(sender() == self.farm, "Access is only for the owner");
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        require(msg.newAdditionalJettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address in mesage cannot be zero");
        if (now() < self.lockEndTime) {
            require(msg.newAdditionalJettonWalletAddress != self.contractJettonCollateralWalletAddress, "Additional jetton wallet address in mesage cannot be collateral jetton wallet");
            require(msg.newAdditionalJettonWalletAddress != self.contractLaunchJettonWalletAddress, "Additional jetton wallet address in mesage cannot be collateral jetton wallet");
        }
        self.additionalJettonWalletAddress = msg.newAdditionalJettonWalletAddress;
        self.transferTokensToWithPayload(self.additionalJettonWalletAddress, self.farm, msg.amount, SendOtherJettonsToFarm{}.toCell(), self.commission * 2, self.commission);
        self.queryId += 1;
    }

    // Adds a new market maker address to the map if it is not already present.
    receive(msg: AddMarketMakerAddresses) {
        require(sender() == self.owner, "Access is only for the owner");
        require((!self.oldContractAddressesMap.exists(msg.newMarketMakerAddresse)), "Old contract address cannot be equal to any of addresses in contract");
        if (!self.marketMakerAddressesMap.exists(msg.newMarketMakerAddresse)) {
            self.marketMakerAddressesLength += 1;
            self.marketMakerAddressesMap.set(msg.newMarketMakerAddresse, self.marketMakerAddressesLength);
        } else {
            self.notify("Market maker address already exists".asComment());
        }
    }

    // Removes a market maker address from the map if it exists.
    receive(msg: DeleteMarketMakerAddresses) {
        require(sender() == self.owner, "Access is only for the owner");
        if (!self.marketMakerAddressesMap.exists(msg.delMarketMakerAddresse)) {
            self.notify("Market maker address does not exist".asComment());
        } else {
            self.marketMakerAddressesMap.del(msg.delMarketMakerAddresse);
            self.marketMakerAddressesLength -= 1;
        }
    }

    // Verifies and registers the old contract address.
    // Requires that the address is non-zero and does not match the main contract addresses.
    // Intended for use when "migrating" to a new contract.
    // A lock is set on the new contract, and a deferred withdrawal is initiated on the old one.
    receive(msg: OldContractAddress) {
        require(!self.checkTradingAccess(), "Lock is not active");
        require(sender() == self.owner, "Access is only for the owner");
        require(msg.oldContractAddress != newAddress(0, 0), "Old contract address cannot be zero");
        require(
            msg.oldContractAddress != self.owner &&
            msg.oldContractAddress != self.reserveOwner &&
            msg.oldContractAddress != self.launchJettonMasterAddress &&
            msg.oldContractAddress != self.contractLaunchJettonWalletAddress &&
            msg.oldContractAddress != self.additionalJettonWalletAddress &&
            msg.oldContractAddress != self.jettonCollateralMasterAddress &&
            msg.oldContractAddress != self.contractJettonCollateralWalletAddress &&
            msg.oldContractAddress != self.returnWalletAddress &&
            msg.oldContractAddress != self.royaltyWalletAddress &&
            msg.oldContractAddress != self.recipientDeferredWithdrawalLaunchJetton &&
            msg.oldContractAddress != self.recipientDeferredWithdrawalCollateralJetton &&
            (!self.marketMakerAddressesMap.exists(msg.oldContractAddress)),
            "Old contract address cannot be equal to any of addresses in contract"
        );
        self.oldContractAddress = msg.oldContractAddress;
        if (!self.oldContractAddressesMap.exists(msg.oldContractAddress)) {
            require(self.oldContractAddressesLength < 256, "Too much old contracts");
            self.oldContractAddressesLength += 1;
            self.oldContractAddressesMap.set(msg.oldContractAddress, self.oldContractAddressesLength);
        }
    }

    // Main handler for incoming messages without parameters (for TON).
    //
    // The logic depends on the collateral mode (self.jettonCollateral) and the sender's address:
    // - If collateral with jettons is enabled and the call comes from the owner or the old contract (oldContractAddress),
    //   it confirms that collateral is active (to protect from inconsistent calls), and ensures the contract is active and jetton wallets are initialized.
    // - If collateral with jettons is disabled, calls from the owner or old contract can adjust the collateral balance
    //   if there is a jetton offset, reducing the collateralBalance debt.
    // - For other calls (e.g., trades from MarketMaker or whitelisted addresses), the following checks apply:
    //   lockEndTime restriction, verification of sender permissions in marketMakerAddressesMap,
    //   and control of fees and balances.
    // - Also includes logic to return change (excess funds) to the owner.
    //
    // Calculates the amount of launch jettons to issue for the received funds (after deducting fees),
    // distributes the profit between the creator and the royalty wallet, and depending on the profit payout mode,
    // either immediately transfers the profit or accumulates it for later withdrawal.
    // Then updates the contract balance and sends jettons to the sender.

    receive() {
        if (self.jettonCollateral && (sender() == self.owner || sender() == self.oldContractAddress)) {
            require(self.jettonCollateral, "Jetton collateral is not used.");
        } else {
            require(self.isInitialized, "Contract jetton wallets are not initialized yet");
            require(!self.jettonCollateral, "Jetton collateral is used");
            let value = context().value - 4 * self.commission;
            require(value >= self.commission, "Insufficient funds to cover commission");
            let gasMinimum = value / (5 * self.quantityJettonsPerLevel * self.currentPrice / (self.jettonDecimals));
            require(gasMinimum < 20, "Too much value for gas");
            if (self.profitInTime) {
                value -= self.commission * (2 + gasMinimum);
            } else {
                value -= self.commission * gasMinimum;
            }
            require(value >= self.commission, "Insufficient funds to cover commission");
            if (sender() == self.owner || sender() == self.oldContractAddress) {
                if (self.offsetJettons - self.jettonsEarned > 0)
                {
                    let deltaCollateralBalance = self.calculateChangeOffsetCollateral(value);
                    self.contractCollateralBalance += deltaCollateralBalance;
                    let change = value - deltaCollateralBalance;
                    if (change > 0) {
                        message(MessageParameters{
                            to: self.owner,
                            value: change,
                            bounce: true,
                            mode: SendPayFwdFeesSeparately,
                            body: "Send change to the owner".asComment()
                        });
                    }
                }
            } else {
                require(self.isActive, "Contract is not active");
                if (!self.checkTradingAccess()) {
                    if (self.checkUnlockWindow()) {
                        self.controlDay += THIRTY_DAYS * self.calculatePastPeriods();
                    }
                    require(self.marketMakerAddressesMap.exists(sender()), "Now can trade only MarketMaker and this address is not a MarketMaker");
                }
                if (self.marketMakerAddressesMap.exists(sender())) {
                    require(value >= self.commission * 2, "Insufficient funds to cover commission");
                } else {
                    require(value >= self.commission, "Insufficient funds to cover commission");
                }
                require(self.contractJettonBalance > self.totalJettonsSold, "Insufficient jetton balance");

                let totalTokens: Int = self.calculateJettonsToGiveForCollateralAmount(value);
                let creatorProfit: Int = self.actualProfit * self.creatorProfitPercent / MAX_PERCENT;
                let royaltyProfit: Int = self.actualProfit * self.royaltyProfitPercent / MAX_PERCENT;

                if (self.profitInTime) {
                    message(MessageParameters{
                        to: self.owner,
                        value: creatorProfit,
                        bounce: true,
                        mode: SendPayFwdFeesSeparately,
                        body: "Send profit to the owner".asComment()
                    });
                    message(MessageParameters{
                        to: self.royaltyWalletAddress,
                        value: royaltyProfit,
                        bounce: true,
                        mode: SendPayFwdFeesSeparately,
                        body: "Send profit to royalty".asComment()
                    });
                } else {
                    self.ownerTonBalance += creatorProfit;
                    self.royaltyTonBalance += royaltyProfit;
                }

                let netValue: Int = value - self.actualProfit;

                self.contractCollateralBalance += netValue;
                self.totalJettonsSold += totalTokens;

                self.transferTokensToWithPayload(self.contractLaunchJettonWalletAddress, sender(), totalTokens, PurchaseIsSuccess{}.toCell(), self.commission * 2, self.commission );

                self.queryId += 1;
            }
        }
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
        let value = context().value;
        require(self.isInitialized, "Contract jetton wallets are not initialized yet");
        require(self.isActive, "Contract is not active");
        if (sender() == self.contractJettonCollateralWalletAddress) {
            try {
                require(self.jettonCollateral, "Jettons collateral is not used or notification not from your jetton collateral wallet!");
                let gasMinimum = 4 + msg.amount / (5 * self.quantityJettonsPerLevel * self.currentPrice / (self.jettonDecimals));
                require(gasMinimum < 20, "Too much value for gas");
                if (self.profitInTime) {
                    require(value >= self.commission * (2 + gasMinimum), "Insufficient funds to cover commission for transfer collateral jettons.");
                } else {
                    require(value >= self.commission * gasMinimum, "Insufficient funds to cover commission for transfer collateral jettons.");
                }
                if (msg.sender == self.owner || msg.sender == self.oldContractAddress) {
                    if (self.offsetJettons - self.jettonsEarned > 0) {
                        let deltaCollateralBalance = self.calculateChangeOffsetCollateral(msg.amount);
                        self.contractCollateralBalance += deltaCollateralBalance;
                        let change = msg.amount - deltaCollateralBalance;
                        if (change > 0) {
                            self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, self.owner, change, SendChangeToOwner{}.toCell(), self.commission * 2, self.commission);
                        }
                    } else {
                        self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, self.owner, value, SendBackToOwner{}.toCell(), self.commission * 2, self.commission);
                    }
                } else {
                    if (!self.checkTradingAccess()) {
                        if (self.checkUnlockWindow()) {
                            self.controlDay += THIRTY_DAYS * self.calculatePastPeriods();
                        }
                        require(self.marketMakerAddressesMap.exists(msg.sender), "Now can trade only MarketMaker and this address is not a MarketMaker");
                    }
                    require(self.contractJettonBalance > self.totalJettonsSold, "Insufficient jetton balance.");

                    let totalTokens: Int = self.calculateJettonsToGiveForCollateralAmount(msg.amount);
                    let creatorProfit: Int = self.actualProfit * self.creatorProfitPercent / MAX_PERCENT;
                    let royaltyProfit: Int = self.actualProfit * self.royaltyProfitPercent / MAX_PERCENT;
                    let netValue: Int = msg.amount - self.actualProfit;

                    if (self.profitInTime) {
                        self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, self.royaltyWalletAddress, royaltyProfit, SendProfitToRoyalty{}.toCell(), self.commission, self.commission / 5);
                        self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, self.owner, creatorProfit, SendProfitToTheOwner{}.toCell(), self.commission, self.commission / 5);
                    } else {
                        self.ownerCollateralBalance += creatorProfit;
                        self.royaltyCollateralBalance += royaltyProfit;
                    }

                    self.contractCollateralBalance += netValue;
                    self.totalJettonsSold += totalTokens;
                    self.transferTokensToWithPayload(self.contractLaunchJettonWalletAddress, msg.sender, totalTokens, PurchaseIsSuccess{}.toCell(), self.commission * 2, self.commission );

                }
            } catch (error) {
                let errorComment: StringBuilder = beginString();
                errorComment.append("Something went wrong (");
                errorComment.append(error.toString());
                errorComment.append(")");
                self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, msg.sender, msg.amount, errorComment.toCell(), self.commission * 2, self.commission);
            }
        } else {
            try {
                require(sender() == self.contractLaunchJettonWalletAddress, "Notification not from your jetton wallet!");
                if (msg.sender == self.owner || msg.sender == self.oldContractAddress) {
                    if (self.callJettonsID == 1) {
                        self.contractJettonBalance += msg.amount;
                        self.callJettonsID = 0;
                    } else {
                        if (self.totalJettonsSold == self.offsetJettons && (self.offsetJettons - self.jettonsEarned) >= msg.amount) {
                            
                            let gasMinimum = 2 + msg.amount / (5 * self.sizeOffsetStep);
                            require(gasMinimum < 20, "Too much value for gas");
                            require(value >= gasMinimum * self.commission, "Amount of TON must be greater than minimal");
                            // @misti:suppress UnusedExpressionResult
                            self.calculateChangeOffsetJetton(msg.amount);
                        } else {
                            self.contractJettonBalance += msg.amount;
                        }
                    }
                } else if (msg.sender == self.returnWalletAddress) {
                    let gasMinimum = 4 + msg.amount / (5 * self.quantityJettonsPerLevelEarned);
                    require(gasMinimum < 20, "Too much value for gas");
                    require(value >= gasMinimum * self.commission, "Amount must be greater than minimal");
                    let amount: Int = msg.amount;
                    let collateralAmountToPay: Int = 0;
                    let tokensAvailableForReturnBuyback: Int = self.totalJettonsSold - self.jettonsEarned;
                    let effectiveAmount: Int = min(amount, tokensAvailableForReturnBuyback);

                    if (self.offsetJettons > self.jettonsEarned) {
                        if (effectiveAmount > self.offsetJettons - self.jettonsEarned) {
                            // @misti:suppress UnusedExpressionResult
                            self.calculateCollateralForTokenAmountEarned(self.offsetJettons - self.jettonsEarned);
                            let buybackAmount: Int = effectiveAmount - (self.offsetJettons - self.jettonsEarned);
                            collateralAmountToPay = self.calculateCollateralForTokenAmountEarned(buybackAmount);
                        } else {
                            // @misti:suppress UnusedExpressionResult
                            self.calculateCollateralForTokenAmountEarned(effectiveAmount);
                            collateralAmountToPay = 0;
                        }
                    } else {
                        collateralAmountToPay = self.calculateCollateralForTokenAmountEarned(effectiveAmount);
                    }

                    self.jettonsEarned += effectiveAmount;
                    require(self.contractCollateralBalance >= collateralAmountToPay, "Insufficient contract balance for redemption");
                    self.contractCollateralBalance -= collateralAmountToPay;
                    self.contractJettonBalance += amount;

                    if (collateralAmountToPay > 0) {
                        if (self.jettonCollateral) {
                            self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, self.farm, collateralAmountToPay, PriceGrowthBuyback{}.toCell(), self.commission * 2, self.commission);
                        } else {
                            message(MessageParameters{
                                to: self.farm,
                                value: collateralAmountToPay,
                                bounce: true,
                                mode: SendPayFwdFeesSeparately,
                                body: PriceGrowthBuyback{}.toCell()
                            });
                        }
                    }
                } else {
                    if (!self.checkTradingAccess()) {
                        if (self.checkUnlockWindow()) {
                            self.controlDay += THIRTY_DAYS * self.calculatePastPeriods();
                        }
                        require(self.marketMakerAddressesMap.exists(msg.sender), "Now can trade only MarketMaker and this address is not a MarketMaker");
                    }

                    let gasMinimum = 4 + msg.amount / (4 * self.quantityJettonsPerLevel);
                    require(gasMinimum < 20, "Too much value for gas");
                    require(value >= gasMinimum * self.commission, "Amount must be greater than minimal");

                    let tokensAvailableForBuyback: Int = self.totalJettonsSold - max(self.offsetJettons, self.jettonsEarned);
                    let tokenForBuyback: Int = msg.amount;
                    require(tokensAvailableForBuyback > 0, "Not have tokensAvailableForBuyback");
                    require(tokensAvailableForBuyback >= tokenForBuyback, "Insufficient tokens available for buyback");

                    let collateralAmountToPay: Int = self.calculateCollateralToPayForTokenAmount(tokenForBuyback);
                    require(self.contractCollateralBalance >= collateralAmountToPay, "Not enough collateral balance");

                    self.contractCollateralBalance -= collateralAmountToPay;
                    self.totalJettonsSold -= tokenForBuyback;

                    if (self.jettonCollateral) {
                        self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, msg.sender, collateralAmountToPay, CollateralBuyback{}.toCell(), self.commission * 2, self.commission);
                    } else {
                        message(MessageParameters{
                            to: msg.sender,
                            value: collateralAmountToPay,
                            bounce: true,
                            mode: SendPayFwdFeesSeparately,
                            body: "Collateral Buyback".asComment()
                        });
                    }
                }
            } catch(error) {
                let errorComment: StringBuilder = beginString();
                errorComment.append("Something went wrong (");
                errorComment.append(error.toString());
                errorComment.append(")");
                self.transferTokensToWithPayload(self.contractLaunchJettonWalletAddress, msg.sender, msg.amount, errorComment.toCell(), self.commission * 2, self.commission);
            }
        }
    }

    // You can use DAO for launch and manage your contract. Reed more aboutt this on https://tokens.family
    receive(msg: SetFarm) {
        require(sender() == self.farm, "Access is only for the farm");
        self.farm = msg.farm;
    }

    // Transfers all unsold jettons to the owner after the lock period ends.
    // Verifies caller's permission and lock time.
    // Resets the contract state to initial parameters.
    receive(msg: WithdrawAllCoins) {
        require(sender() == self.farm, "Access is only for the farm");
        require(now() >= self.lockEndTime, "Lock period has not ended yet!");
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        self.transferTokensToWithPayload(self.contractLaunchJettonWalletAddress, self.farm, self.contractJettonBalance - self.totalJettonsSold, TransferAllLaunchJettonsToOwner{}.toCell(), self.commission * 2, self.commission);
        self.contractJettonBalance = 0;
        self.isActive = false;
    }

    // Transfers the entire collateral jetton balance to the owner after the lock period ends.
    // Verifies caller's permission, lock time, and collateral mode.
    // Resets the collateral balance after the transfer.
    receive(msg: WithdrawAllCollateralCoins) {
        require(sender() == self.farm, "Access is only for the farm");
        require(now() >= self.lockEndTime, "Lock period has not ended yet!");
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        require(self.jettonCollateral, "Jetton collateral is not used.");
        self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, self.farm, self.contractCollateralBalance, SendAllCollateralBalanceToOwner{}.toCell(), self.commission * 2, self.commission);
        self.contractCollateralBalance = 0;
        self.isActive = false;
    }

    // Transfers the entire available TON balance to the owner after the lock period ends.
    // Verifies caller's permission and lock time.
    // Resets the collateral balance and updates the TON balance used for fees.
    receive(msg: WithdrawAllTons) {
        require(sender() == self.farm, "Access is only for the farm");
        require(now() >= self.lockEndTime, "Lock period has not ended yet!");
        let amount: Int = myBalance() - context().value - self.commission;
        message(MessageParameters{
            to: self.farm,
            value: amount,
            mode: SendIgnoreErrors | SendRemainingValue,
            bounce: true,
            body: PaybackToFarm{}.toCell()
        });
        self.contractCollateralBalance = 0;
        self.isActive = false;
    }

    // Sends unused TON to the owner.
    // Takes into account the collateral mode and deducts the fee.
    receive(msg: WithdrawUnusedTons) {
        require(sender() == self.owner, "Access is only for the owner");
        let unusedTonToWithdraw: Int = 0;
        if (self.jettonCollateral) {
            unusedTonToWithdraw = myBalance() - (self.commission * COMMISSION_MULTIPLIER);
        } else {
            unusedTonToWithdraw = myBalance() - self.contractCollateralBalance - self.ownerTonBalance - self.royaltyTonBalance - (self.commission * COMMISSION_MULTIPLIER);
        }
        message(MessageParameters{
            to: self.owner,
            value: unusedTonToWithdraw,
            mode: SendPayFwdFeesSeparately | SendBounceIfActionFail,
            bounce: true,
            body: "Send unused tons to the owner".asComment()
        });
    }

    // Sends profit to the current owner or the royalty wallet depending on the requester's rights.
    receive(msg: GetProfitOnRequest) {
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        if (sender() == self.owner()) {
            if (self.jettonCollateral) {
                self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, sender(), self.ownerCollateralBalance, SendProfitToTheOwner{}.toCell(), self.commission * 2, self.commission );
                self.ownerCollateralBalance = 0;
            } else {
                message(MessageParameters{
                    to: sender(),
                    value: self.ownerTonBalance,
                    bounce: true,
                    mode: SendPayFwdFeesSeparately,
                    body: "Send profit to the owner".asComment()
                });
                self.ownerTonBalance = 0;
            }
        } else {
            require(sender() == self.royaltyWalletAddress, "Access is only for current owner or royalty wallet");
            if (self.jettonCollateral) {
                self.transferTokensToWithPayload(self.contractJettonCollateralWalletAddress, sender(), self.royaltyCollateralBalance, SendProfitToRoyalty{}.toCell(), self.commission * 2, self.commission);
                self.royaltyCollateralBalance = 0;
            } else {
                 message(MessageParameters{
                    to: sender(),
                    value: self.royaltyTonBalance,
                    bounce: true,
                    mode: SendPayFwdFeesSeparately,
                    body: "Send profit to royalty".asComment()
                });
                self.royaltyTonBalance = 0;
            }
        }
    }

    // Sends the sender information about the lock end time and deferred withdrawals.
    receive(msg: FetchLockEndTime) {
        require(context().value >= self.commission, "Insufficient funds to cover commission for transfer lock end time");
        message(MessageParameters{
            to: sender(),
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: GetLockEndTime{ queryId: msg.queryId, originalGasTo: msg.originalGasTo, lockEndTime: self.lockEndTime, launchJettonDeferredWTHDate: self.launchJettonDeferredWithdrawalDate, collateralJettonDeferredWTHDate: self.collateralJettonDeferredWithdrawalDate }.toCell()});
    }

    // Sends the current price of the launch jetton to the sender.
    receive(msg: FetchCurrentPrice) {
        require(context().value >= self.commission, "Insufficient funds to cover commission for price");
        message(MessageParameters{
            to: sender(),
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: GetCurrentPrice{ queryId: msg.queryId, originalGasTo: msg.originalGasTo, currentPrice: self.currentPrice }.toCell()});
    }

    // Sends the number of market makers.
    receive(msg: FetchNumberOfMarketMakers) {
        require(context().value >= self.commission, "Insufficient funds to cover commission for transfer number of market makers");
        message(MessageParameters{
            to: sender(),
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: GetNumberOfMarketMakers{ queryId: msg.queryId, originalGasTo: msg.originalGasTo, currentNumber: self.marketMakerAddressesLength }.toCell()});
    }
    // jetton collateral, launch token, active, current price
    receive(msg: FetchContractInfoAfterUpdatePoc) {
        require(context().value >= self.commission, "Insufficient funds to cover commission for transfer jetton collateral");
        message(MessageParameters{
            to: sender(),
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: GetContractInfoAfterUpdatePoc{ queryId: msg.queryId, originalGasTo: msg.originalGasTo, jettonCollateralAddress: self.jettonCollateralMasterAddress, jettonLaunchAddress: self.launchJettonMasterAddress, isActive: self.isActive, currentPrice: self.currentPrice }.toCell()});
    }

    // Calculates the number of full 30-day periods elapsed since controlDay.
    fun calculatePastPeriods(): Int {
        return (now() - self.controlDay) / THIRTY_DAYS;
    }

    // Checks if the current time is within the controlled period after controlDay.
    fun checkControlDay(): Bool {
        if (now() - self.controlDay > THIRTY_DAYS && (now() - self.controlDay - THIRTY_DAYS) < self.controlPeriod) {
            return true;
        } else {
            return false;
        }
    }

    // Helper function to check if the caller is allowed to trade at the current moment.
    fun checkTradingAccess(): Bool {
        return (self.launchJettonDeferredWithdrawalDate > 0) || (self.collateralJettonDeferredWithdrawalDate > 0) || self.lockEndTime - SIXTY_DAYS < now() || self.checkControlDay();
    }

    // Helper function to check if the current time is within the "unlock window" period after the lock expires.
    fun checkUnlockWindow(): Bool {
        return (now() - self.controlDay - THIRTY_DAYS > self.controlPeriod);
    }

    // Sends the specified amount of jettons with a comment to the given address.
    fun transferTokensToWithPayload(toAddress: Address, recipient: Address, amount: Int, payload: Cell, value: Int, forwardTonAmount: Int) {

        let forwardPayload = beginCell().storeBit(false).storeSlice(payload.asSlice()).asSlice();
        message(MessageParameters{
            to: toAddress,
            value: value,
            body: JettonTransfer{
                queryId: self.queryId,
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
        if (currentStep > self.trendChangeStep) {
            return self.profitPercentage;
        } else {
            return self.profitPercentage * self.coefficientProfit / MAX_PERCENT;
        }
    }

    // Calculates the number of tokens per level taking into account the current step and multipliers.
    fun calculateJettonsPerLevel(jettonsPerLevel: Int, currentStep: Int): Int {
        if (currentStep > self.trendChangeStep) {
            return (jettonsPerLevel * (MAX_PERCENT - self.levelDecreaseMultiplierafterTrend)) / MAX_PERCENT;
        } else {
            return (jettonsPerLevel * (MAX_PERCENT + self.levelIncreaseMultiplier)) / MAX_PERCENT;
        }
    }

    // Calculates the offset for a given amount of tokens, updating the step state,
    // step remainder, step size, and current price.
    //
    // Logic:
    // - Calculates how many tokens can be distributed at the current step (remainderOfStep).
    // - If the amount of tokens exceeds the step remainder, moves to the next step:
    //   - Increments the step number.
    //   - Recalculates the number of tokens per level for the new step.
    //   - Increases the price using the increment multiplier.
    // - If the tokens are less than or equal to the step remainder, decreases the remainder by this amount.
    // - Updates global contract variables for the current step, price, token quantity, and balance.
    fun calculateOffset(amountJettons: Int) {
        let remainingOffsetJettons: Int = amountJettons;
        let localCurrentStep: Int = self.offsetStep;
        let remainderOfStep: Int = self.remainderOffsetJettons;
        let jettonsPerLevel: Int = self.sizeOffsetStep;
        let currentPrice: Int = self.currentPrice;

        while (remainingOffsetJettons > 0) {
            let tokensAvailableInStep: Int = remainderOfStep;

            if (remainingOffsetJettons >= tokensAvailableInStep) {
                remainingOffsetJettons -= tokensAvailableInStep;
                localCurrentStep += 1;

                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStep = jettonsPerLevel;
                currentPrice = (currentPrice * (MAX_PERCENT + self.priceIncrementMultiplier)) / MAX_PERCENT;
            } else {
                remainderOfStep -= remainingOffsetJettons;
                remainingOffsetJettons = 0;
            }
        }

        self.offsetStep = localCurrentStep;
        self.remainderOffsetJettons = remainderOfStep;
        self.sizeOffsetStep = jettonsPerLevel;
        self.offsetPrice = currentPrice;

        self.currentStep = localCurrentStep;
        self.quantityJettonsPerLevel = jettonsPerLevel;
        self.currentPrice = currentPrice;

        self.remainderOfStep = remainderOfStep;
        self.contractJettonBalance = amountJettons;
        self.totalJettonsSold = amountJettons;
    }

    // Calculates the offset change for collateral based on the given collateral amount,
    // updating the internal offset and step state.
    //
    // Logic:
    // - Iterates over the remaining collateral amount and available offset tokens.
    // - For each step, calculates the available number of tokens, profit percentage, and actual collateral cost.
    // - If the remaining collateral and tokens cover the entire step, decreases the remainder and step count,
    //   adjusts step parameters and price.
    // - If the collateral is less than the full step cost, distributes tokens partially and updates remainders.
    // - Updates the current step, price, and offset remainder parameters.
    //
    // Returns:
    // - The amount of collateral successfully distributed across steps.
    fun calculateChangeOffsetCollateral(amountCollateral: Int): Int {
        let remainingAddCollateral: Int = amountCollateral;
        let remainingOffsetJettons: Int = self.offsetJettons;
        let remainingAddJettons: Int = self.offsetJettons - self.jettonsEarned;
        let localCurrentStep: Int = self.offsetStep;
        let remainderOfStep: Int = self.remainderOffsetJettons;
        let jettonsPerLevel: Int = self.sizeOffsetStep;
        let currentPrice: Int = self.offsetPrice;

        while (remainingAddCollateral > 0 && remainingAddJettons > 0) {
            let tokensAvailableInStep: Int = jettonsPerLevel - remainderOfStep;
            let profitPercentage: Int = self.calculateProfit(localCurrentStep);
            let tonInStep: Int = tokensAvailableInStep * currentPrice / self.jettonDecimals;
            let tonRealInStep: Int = tonInStep * (MAX_PERCENT - profitPercentage) / MAX_PERCENT;

            if (remainingAddCollateral >= tonRealInStep && remainingAddJettons >= tokensAvailableInStep) {
                remainingAddCollateral -= tonRealInStep;
                remainingOffsetJettons -= tokensAvailableInStep;
                remainingAddJettons -= tokensAvailableInStep;

                if (localCurrentStep > self.currentStepEarned) {
                    if (localCurrentStep > self.trendChangeStep) {
                        jettonsPerLevel = jettonsPerLevel * MAX_PERCENT / (MAX_PERCENT - self.levelDecreaseMultiplierafterTrend);
                    } else {
                        jettonsPerLevel = jettonsPerLevel * MAX_PERCENT / (MAX_PERCENT + self.levelIncreaseMultiplier);
                    }
                    currentPrice = currentPrice * MAX_PERCENT / (MAX_PERCENT + self.priceIncrementMultiplier);
                }

                if (localCurrentStep > self.currentStepEarned) {
                    localCurrentStep -= 1;
                    remainderOfStep = 0;
                } else {
                    localCurrentStep = self.currentStepEarned;
                    remainderOfStep = jettonsPerLevel;
                    remainingAddJettons = 0;
                }

            } else {
                let adjustedPrice: Int = currentPrice * (MAX_PERCENT - profitPercentage) / MAX_PERCENT;

                let collateralToPayForStep: Int = 0;
                let tokensToBuyInThisStep: Int = 0;


                if (remainingAddCollateral >= tonRealInStep) {
                    collateralToPayForStep = remainingAddJettons * adjustedPrice / self.jettonDecimals;
                    tokensToBuyInThisStep = remainingAddJettons;
                } else {
                    collateralToPayForStep = remainingAddCollateral;
                    tokensToBuyInThisStep = remainingAddCollateral * self.jettonDecimals / adjustedPrice;
                }
                remainderOfStep += tokensToBuyInThisStep;
                remainingAddCollateral -= collateralToPayForStep;
                remainingOffsetJettons -= tokensToBuyInThisStep;
                remainingAddJettons = 0;
            }
        }

        self.offsetStep = localCurrentStep;
        self.remainderOffsetJettons = remainderOfStep;
        self.offsetPrice = currentPrice;
        self.sizeOffsetStep = jettonsPerLevel;
        self.offsetJettons = remainingOffsetJettons;

        return (amountCollateral - remainingAddCollateral);
    }

    // Updates the offset for a given amount of added tokens,
    // adjusting the current step, remainder, and price.
    //
    // Main steps:
    // - Iterates over the remaining amount of tokens to be added.
    // - For each step, calculates the available number of tokens.
    // - If the added tokens are enough to fill the step, decreases the remainder,
    //   and updates step parameters and price based on the current level.
    // - If the tokens are not enough, partially increases the step remainder.
    // - Updates global offset parameters and the current step.
    // - Decreases the total number of sold tokens by the added amount.
    //
    // Returns:
    // - The current step after recalculation.
    fun calculateChangeOffsetJetton(amountJetton: Int): Int {
        let remainingAddJettons: Int = amountJetton;
        let localCurrentStep: Int = self.offsetStep;
        let remainderOfStep: Int = self.remainderOffsetJettons;
        let jettonsPerLevel: Int = self.sizeOffsetStep;
        let currentPrice: Int = self.offsetPrice;

        while (remainingAddJettons > 0) {
            let tokensAvailableInStep: Int = jettonsPerLevel - remainderOfStep;

            if (remainingAddJettons >= tokensAvailableInStep) {
                remainingAddJettons -= tokensAvailableInStep;

                if (localCurrentStep > self.currentStepEarned) {
                    if (localCurrentStep > self.trendChangeStep) {
                        jettonsPerLevel = jettonsPerLevel * MAX_PERCENT / (MAX_PERCENT - self.levelDecreaseMultiplierafterTrend);
                    } else {
                        jettonsPerLevel = jettonsPerLevel * MAX_PERCENT / (MAX_PERCENT + self.levelIncreaseMultiplier);
                    }
                    currentPrice = currentPrice * MAX_PERCENT / (MAX_PERCENT + self.priceIncrementMultiplier);
                }

                if (localCurrentStep > self.currentStepEarned) {
                    localCurrentStep -= 1;
                    remainderOfStep = 0;
                } else {
                    localCurrentStep = self.currentStepEarned;
                    remainderOfStep = jettonsPerLevel;
                    remainingAddJettons = 0;
                }

            } else {
                remainderOfStep += remainingAddJettons;
                remainingAddJettons = 0;
            }
        }

        self.offsetStep = localCurrentStep;
        self.remainderOffsetJettons = remainderOfStep;
        self.offsetPrice = currentPrice;
        self.sizeOffsetStep = jettonsPerLevel;

        self.offsetJettons -= amountJetton;

        self.currentStep = localCurrentStep;
        self.quantityJettonsPerLevel = jettonsPerLevel;
        self.currentPrice = currentPrice;

        self.remainderOfStep = remainderOfStep;
        self.totalJettonsSold -= amountJetton;
        return localCurrentStep;
    }

    // Calculates the number of tokens to be issued for a given collateral amount.
    //
    // Logic:
    // - Initializes local variables for the current step, remainder, tokens per level, and price.
    // - In a loop, while there is remaining collateral and tokens available to issue:
    //   - Determines the available number of tokens at the current step and the required TON amount to purchase them.
    //   - If the collateral is sufficient for a full step:
    //     - Increases the number of tokens to issue by the full step amount.
    //     - Calculates and accumulates profit for that step.
    //     - Moves to the next step, recalculating tokens per level and price.
    //   - If the collateral is insufficient for a full step:
    //     - Calculates how many tokens can be bought with the remaining collateral.
    //     - Adds them to the total number to be issued.
    //     - Calculates and adds profit for this partial step.
    //     - Sets the remaining collateral to zero and adjusts the step remainder.
    // - If more tokens are requested than available, limits issuance to the maximum remaining.
    // - Updates offset state, current step, price, and profit.
    //
    // Returns:
    // - The number of tokens to be issued.
    fun calculateJettonsToGiveForCollateralAmount(collateralAmount: Int): Int {
        let jettonsToGive: Int = 0;
        let remainingCollateralAmount: Int = collateralAmount;
        let localCurrentStep: Int = self.currentStep;
        let remainderOfStep: Int = self.remainderOfStep;
        let jettonsPerLevel: Int = self.quantityJettonsPerLevel;
        let currentPrice: Int = self.currentPrice;
        let totalProfit: Int = 0;
        let remainderOfjettons: Int = self.contractJettonBalance - self.totalJettonsSold;

        while (remainingCollateralAmount > 0 && remainderOfjettons >= jettonsToGive) {
            let tokensAvailableInStep: Int = remainderOfStep;
            let tonRequiredForStep: Int = tokensAvailableInStep * currentPrice / self.jettonDecimals;

            if (remainingCollateralAmount >= tonRequiredForStep) {
                jettonsToGive += tokensAvailableInStep;
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let profitInStep: Int = (tonRequiredForStep * profitPercentage) / MAX_PERCENT;

                totalProfit += profitInStep;

                remainingCollateralAmount -= tonRequiredForStep;

                localCurrentStep += 1;

                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);

                remainderOfStep = jettonsPerLevel;
                currentPrice = (currentPrice * (MAX_PERCENT + self.priceIncrementMultiplier)) / MAX_PERCENT;
            } else {
                let tokensToBuyInThisStep: Int = remainingCollateralAmount * self.jettonDecimals / currentPrice;
                jettonsToGive += tokensToBuyInThisStep;
                let tonSpentInThisStep: Int = remainingCollateralAmount;

                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let profitInStep: Int = (tonSpentInThisStep * profitPercentage) / MAX_PERCENT;

                totalProfit += profitInStep;

                remainingCollateralAmount = 0;
                remainderOfStep -= tokensToBuyInThisStep;
            }
        }

        if (remainderOfjettons < jettonsToGive) {
            jettonsToGive = remainderOfjettons;
        }

        self.currentStep = localCurrentStep;
        self.quantityJettonsPerLevel = jettonsPerLevel;
        self.currentPrice = currentPrice;
        self.actualProfit = totalProfit;

        if (remainderOfStep < 0) {
            self.remainderOfStep = 0;
        } else {
            self.remainderOfStep = remainderOfStep;
        }

        return jettonsToGive;
    }

    // Calculates the collateral amount (collateralAmountToPay) required to purchase a given number of tokens (tokenAmount).
    //
    // Logic:
    // - Uses local copies of the current step, step token remainder, price, and tokens per level.
    // - While there are tokens left to pay for:
    //   - Determines the number of tokens available at the current step.
    //   - If the remaining token amount is greater than or equal to the available tokens in the step:
    //     - Calculates the profit percentage for the current step.
    //     - Adjusts the price with the profit.
    //     - Calculates the collateral amount for the full step and adds it to the total payment.
    //     - Reduces the remaining token amount.
    //     - Updates level parameters and price when transitioning to a new step.
    //     - Adjusts the step and step token remainder based on the current state.
    //   - If the token amount is less than the available tokens in the step:
    //     - Calculates the collateral amount for the partial token quantity similarly.
    //     - Updates the step token remainder.
    //     - All tokens are paid — the loop ends.
    // - Updates the contract state: current step, tokens per level, current price, and remainder.
    //
    // Returns:
    // - The total collateral amount to be paid.
    fun calculateCollateralToPayForTokenAmount(tokenAmount: Int): Int {
        let collateralAmountToPay: Int = 0;
        let remainingJettonAmount: Int = tokenAmount;
        let localCurrentStep: Int = self.currentStep;
        let remainderOfStep: Int = self.remainderOfStep;
        let jettonsPerLevel: Int = self.quantityJettonsPerLevel;
        let currentPrice: Int = self.currentPrice;

        while (remainingJettonAmount > 0) {
            let tokensAvailableInStep: Int = jettonsPerLevel - remainderOfStep;

            if (remainingJettonAmount >= tokensAvailableInStep) {
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);


                let adjustedPrice: Int = currentPrice * (MAX_PERCENT - profitPercentage) / MAX_PERCENT;
                let collateralToPayForStep: Int = tokensAvailableInStep * adjustedPrice / self.jettonDecimals;
                collateralAmountToPay += collateralToPayForStep;

                remainingJettonAmount -= tokensAvailableInStep;

                if (localCurrentStep > self.currentStepEarned) {
                    if (localCurrentStep > self.trendChangeStep) {
                        jettonsPerLevel = jettonsPerLevel * MAX_PERCENT / (MAX_PERCENT - self.levelDecreaseMultiplierafterTrend);
                    } else {
                        jettonsPerLevel = jettonsPerLevel * MAX_PERCENT / (MAX_PERCENT + self.levelIncreaseMultiplier);
                    }
                    currentPrice = currentPrice * MAX_PERCENT / (MAX_PERCENT + self.priceIncrementMultiplier);
                }
                if (localCurrentStep > self.currentStepEarned) {
                    localCurrentStep -= 1;
                    remainderOfStep = 0;
                } else {
                    localCurrentStep = self.currentStepEarned;
                    remainderOfStep = jettonsPerLevel;
                    remainingJettonAmount = 0;
                }


            } else {
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let adjustedPrice: Int = currentPrice * (MAX_PERCENT - profitPercentage) / MAX_PERCENT;
                let collateralToPayForStep: Int = remainingJettonAmount * adjustedPrice / self.jettonDecimals;
                collateralAmountToPay += collateralToPayForStep;

                remainderOfStep += remainingJettonAmount;
                remainingJettonAmount = 0;
            }
        }

        self.currentStep = localCurrentStep;
        self.quantityJettonsPerLevel = jettonsPerLevel;
        self.currentPrice = currentPrice;

        if (remainderOfStep < 0) {
            self.remainderOfStep = 0;
        } else {
            self.remainderOfStep = remainderOfStep;
        }

        return collateralAmountToPay;
    }

    // Calculates the collateral amount (collateralAmountToPay) required to be paid for a given number of earned tokens (tokenAmount).
    //
    // Logic:
    // - Uses local copies of current step, step token remainder, price, and tokens per level for earned.
    // - While there are tokens left to pay for and the current step does not exceed the maximum step:
    //   - Determines the number of tokens available at the current step (remainder).
    //   - If the remaining token amount is greater than or equal to the available remainder:
    //     - Calculates the profit percentage for the current step.
    //     - Adjusts the price including the profit.
    //     - Calculates the collateral amount for the full remainder and adds it to the total payment.
    //     - Proceeds to the next step.
    //     - Updates the number of tokens per level (jettonsPerLevel) using the calculateJettonsPerLevel function.
    //     - Sets the new remainder to the updated tokens per level.
    //     - Decreases the remaining token amount.
    //     - Updates the current price using the increment multiplier.
    //   - If fewer tokens remain than available in the remainder:
    //     - Similarly calculates the collateral amount for the partial token quantity.
    //     - Updates the remainder by subtracting the paid tokens.
    //     - Ends the loop (all tokens are paid).
    // - After the loop, updates the contract state (current earned step, tokens per level, current price, and remainder).
    //
    // Returns:
    // - The total collateral amount to be paid.
    fun calculateCollateralForTokenAmountEarned(tokenAmount: Int): Int {
        let collateralAmountToPay: Int = 0;
        let remainingJettonAmount: Int = tokenAmount;
        let localCurrentStep: Int = self.currentStepEarned;
        let remainderOfStep: Int = self.remainderOfStepEarned;
        let jettonsPerLevel: Int = self.quantityJettonsPerLevelEarned;
        let currentPrice: Int = self.currentPriceEarned;

        while (remainingJettonAmount > 0 && localCurrentStep <= self.currentStep) {
            let tokensAvailableInStep: Int = remainderOfStep;

            if (remainingJettonAmount >= tokensAvailableInStep) {
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let adjustedPrice: Int = currentPrice * (MAX_PERCENT - profitPercentage) / MAX_PERCENT;
                let collateralToPayForStep: Int = tokensAvailableInStep * adjustedPrice / self.jettonDecimals;
                collateralAmountToPay += collateralToPayForStep;

                localCurrentStep += 1;

                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStep = jettonsPerLevel;
                remainingJettonAmount -= tokensAvailableInStep;

                currentPrice = currentPrice * (MAX_PERCENT + self.priceIncrementMultiplier) / MAX_PERCENT;
            } else {
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let adjustedPrice: Int = currentPrice * (MAX_PERCENT - profitPercentage) / MAX_PERCENT;

                let collateralToPayForStep: Int = remainingJettonAmount * adjustedPrice / self.jettonDecimals;
                collateralAmountToPay += collateralToPayForStep;

                remainderOfStep -= remainingJettonAmount;
                remainingJettonAmount = 0;
            }
        }

        self.currentStepEarned = localCurrentStep;
        self.quantityJettonsPerLevelEarned = jettonsPerLevel;
        self.currentPriceEarned = currentPrice;

        if (remainderOfStep < 0) {
            self.remainderOfStepEarned = 0;
        } else {
            self.remainderOfStepEarned = remainderOfStep;
        }

        return collateralAmountToPay;
    }

    get fun remaining_seconds(): Int {
        return self.lockEndTime - now();
    }

    get fun trading_opportunity(): Bool {
        return self.lockEndTime - now() < SIXTY_DAYS;
    }

    get fun lock_end_time(): Int {
        return self.lockEndTime;
    }

    get fun jetton_balance(): Int {
        return self.contractJettonBalance;
    }

    get fun jetton_sold(): Int {
        return self.totalJettonsSold;
    }

    get fun jetton_available(): Int {
        return self.totalJettonsSold - self.jettonsEarned;
    }

    get fun collateral_token_balance(): Int {
        return self.contractCollateralBalance;
    }

    get fun profit(): Int {
        return self.profitPercentage;
    }

    get fun balance(): Int {
        return myBalance();
    }

    get fun quantity_jettons_per_level(): Int {
        return self.quantityJettonsPerLevel;
    }

    get fun current_price(): Int {
        return self.currentPrice;
    }

    get fun remainder_of_step(): Int {
        return self.remainderOfStep;
    }

    get fun check_market_maker_address(address: Address): String {
        if (!self.marketMakerAddressesMap.exists(address)) {
            return "not found";
        } else {
            let addr: String = address.toString();
            let id: Int = self.marketMakerAddressesMap.get(address)!!;
            let output: StringBuilder = beginString();
            output.append(addr);
            output.append(" - ");
            output.append(id.toString());
            return output.toString();
        }
    }

    get fun check_switch_profit(): Bool {
        return self.profitInTime;
    }

    get fun check_owner_profit(): Int {
        if (!self.jettonCollateral) {
            return self.ownerTonBalance;
        } else {
            return self.ownerCollateralBalance;
        }
    }

    get fun check_royalty_profit(): Int {
        if (!self.jettonCollateral) {
            return self.royaltyTonBalance;
        } else {
            return self.royaltyCollateralBalance;
        }
    }

    get fun check_quantity_market_makers(): Int {
        return self.marketMakerAddressesLength;
    }

    get fun return_wallet_address(): Address {
        return self.returnWalletAddress;
    }

    get fun owner_address(): Address {
        return self.owner;
    }

    get fun reserve_owner_address(): Address {
        return self.reserveOwner;
    }

    get fun jetton_wallet_address(): Address {
        return self.contractLaunchJettonWalletAddress;
    }

    get fun jetton_master_address(): Address {
        return self.launchJettonMasterAddress;
    }

    get fun current_step(): Int {
        return self.currentStep;
    }

    get fun step_remainder(): Int {
        return self.remainderOfStep;
    }

    get fun collateral_to_jetton_calculation(a: Int): Int {
        let b: Int = self.calculateJettonsToGiveForCollateralAmount(a);
        return b;
    }

    get fun jetton_to_collateral_calculation(a: Int): Int {
        let b: Int = self.calculateCollateralToPayForTokenAmount(a);
        return b;
    }

    get fun jetton_to_return_calculation(a: Int): Int {
        let b: Int = self.calculateCollateralForTokenAmountEarned(a);
        return b;
    }

    get fun contract_address(): Address {
        return myAddress();
    }


    get fun additional_jetton_wallet_address(): Address {
        return self.additionalJettonWalletAddress;
    }

    get fun unused_collateral_ton(): Int {
        let unusedAmount: Int = myBalance() - self.contractCollateralBalance - (self.commission * COMMISSION_MULTIPLIER);
        return unusedAmount;
    }

    get fun control_day(): Int {
        return self.controlDay;
    }

    get fun control_period(): Int {
        return self.controlPeriod;
    }

    get fun current_commission(): Int {
        return self.commission;
    }

    get fun offset_jettons(): Int {
        return self.offsetJettons;
    }

    get fun offset_step(): Int {
        return self.offsetStep;
    }

    get fun offset_price(): Int {
        return self.offsetPrice;
    }

    get fun remainder_offset_jettons(): Int {
        return self.remainderOffsetJettons;
    }

    get fun size_offset_step(): Int {
        return self.sizeOffsetStep;
    }

    get fun call_jetton_notification_ID(): Int {
        return self.callJettonsID;
    }

    get fun calculate_change_offset_collateral(a: Int): Int {
        let b: Int = self.calculateChangeOffsetCollateral(a);
        return b;
    }

    get fun calculate_change_offset_jetton(a: Int): Int {
        let b: Int = self.calculateChangeOffsetJetton(a);
        return b;
    }

    get fun is_jetton_collateral(): Bool {
        return self.jettonCollateral;
    }

    get fun jetton_collateral_master_address(): Address {
        return self.jettonCollateralMasterAddress;
    }

    get fun contract_jetton_collateral_wallet_address(): Address {
        return self.contractJettonCollateralWalletAddress;
    }

    get fun royalty_profit_percent(): Int {
        return self.royaltyProfitPercent;
    }

    get fun creator_profit_percent(): Int {
        return self.creatorProfitPercent;
    }

    get fun main_jetton_deferred_WTH_Date(): Int {
        return self.launchJettonDeferredWithdrawalDate;
    }

    get fun main_jetton_deferred_WTH_Recipient(): Address {
        return self.recipientDeferredWithdrawalLaunchJetton;
    }

    get fun main_jetton_deferred_WTH_Amount(): Int {
        return self.launchJettonDeferredWithdrawalAmount;
    }

    get fun collateral_jetton_deferred_WTH_Date(): Int {
        return self.collateralJettonDeferredWithdrawalDate;
    }

    get fun collateral_jetton_deferred_WTH_Recipient(): Address {
        return self.recipientDeferredWithdrawalCollateralJetton;
    }

    get fun old_contract_address(): Address {
        return self.oldContractAddress;
    }

    get fun is_active(): Bool {
        return self.isActive;
    }

    get fun is_initialized(): Bool {
        return self.isInitialized;
    }

    get fun check_trading_access(): Bool {
        return self.checkTradingAccess();
    }

    get fun check_current_unlock_window(): Bool {
        return self.checkUnlockWindow();
    }

    get fun dates_contract_state(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("LED:");
        contractState.append(self.lockEndTime.toString());
        contractState.append("|CD:");
        contractState.append(self.controlDay.toString());
        contractState.append("|CP:");
        contractState.append(self.controlPeriod.toString());
        return contractState.toString();
    }

    get fun standard_contract_state_jetton_values(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("IPPT:");
        contractState.append(self.initialPricePerToken.toCoinsString());
        contractState.append("|FLJQ:");
        contractState.append(self.firstLevelJettonQuantity.toCoinsString());
        contractState.append("|TJS:");
        contractState.append(self.totalJettonsSold.toCoinsString());
        contractState.append("|CJB:");
        contractState.append(self.contractJettonBalance.toCoinsString());
        contractState.append("|JE:");
        contractState.append(self.jettonsEarned.toCoinsString());
        contractState.append("|QJPL:");
        contractState.append(self.quantityJettonsPerLevel.toCoinsString());
        contractState.append("|CS:");
        contractState.append(self.currentStep.toString());
        contractState.append("|QJPLE:");
        contractState.append(self.quantityJettonsPerLevelEarned.toCoinsString());
        return contractState.toString();
    }

    get fun collateral_tokens_contract_values(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("JSMA:");
        contractState.append(self.jettonCollateralMasterAddress.toString());
        contractState.append("|CJSWA:");
        contractState.append(self.contractJettonCollateralWalletAddress.toString());
        contractState.append("|CSB:");
        contractState.append(self.contractCollateralBalance.toCoinsString());
        return contractState.toString();
    }

    get fun standard_contract_state_collateral_values(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("PIM:");
        contractState.append(self.priceIncrementMultiplier.toString());
        contractState.append("|C:");
        contractState.append(self.commission.toCoinsString());
        contractState.append("|LIM:");
        contractState.append(self.levelIncreaseMultiplier.toString());
        contractState.append("|TCS:");
        contractState.append(self.trendChangeStep.toString());
        contractState.append("|LDMAT:");
        contractState.append(self.levelDecreaseMultiplierafterTrend.toString());
        contractState.append("|PP:");
        contractState.append(self.profitPercentage.toString());
        contractState.append("|QI:");
        contractState.append(self.queryId.toString());
        contractState.append("|CSB:");
        contractState.append(self.contractCollateralBalance.toCoinsString());
        contractState.append("|CRTB: ");
        contractState.append(myBalance().toCoinsString());
        contractState.append("|AP:");
        contractState.append(self.actualProfit.toCoinsString());
        contractState.append("|CP:");
        contractState.append(self.currentPrice.toCoinsString());
        contractState.append("|ROS:");
        contractState.append(self.remainderOfStep.toCoinsString());
        contractState.append("|CSE:");
        contractState.append(self.currentStepEarned.toCoinsString());
        contractState.append("|ROSE:");
        contractState.append(self.remainderOfStepEarned.toCoinsString());
        contractState.append("|CPE:");
        contractState.append(self.currentPriceEarned.toCoinsString());
        return contractState.toString();
    }

    get fun contract_state_offset_values(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("OJ:");
        contractState.append(self.offsetJettons.toCoinsString());
        contractState.append("|OS:");
        contractState.append(self.offsetStep.toCoinsString());
        contractState.append("|OP:");
        contractState.append(self.offsetPrice.toCoinsString());
        contractState.append("|ROJ:");
        contractState.append(self.remainderOffsetJettons.toCoinsString());
        contractState.append("|SOS:");
        contractState.append(self.sizeOffsetStep.toCoinsString());
        contractState.append("|CJID:");
        contractState.append(self.callJettonsID.toString());
        return contractState.toString();
    }

    get fun other_contract_state_values(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("MMI:");
        contractState.append(self.marketMakerAddressesLength.toString());
        return contractState.toString();
    }

    get fun contract_wth_state_values(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("MJDWD:");
        contractState.append(self.launchJettonDeferredWithdrawalDate.toString());
        contractState.append("|MJDWA:");
        contractState.append(self.launchJettonDeferredWithdrawalAmount.toCoinsString());
        contractState.append("|SJDD:");
        contractState.append(self.collateralJettonDeferredWithdrawalDate.toString());
        return contractState.toString();
    }


    get fun contract_constant_values(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("TYC:");
        contractState.append(TWO_YEARS.toString());
        contractState.append("|HYC:");
        contractState.append(HALF_YEAR.toString());
        contractState.append("|TMC:");
        contractState.append(THREE_MONTHS.toString());
        contractState.append("|TMC:");
        contractState.append(TEN_MINUTES.toString());
        contractState.append("|CC:");
        contractState.append(FIVE_HUNDREDTHS_TON.toCoinsString());
        contractState.append("|SDC:");
        contractState.append(THIRTY_DAYS.toString());
        contractState.append("|MCP:");
        contractState.append(MIN_CONTROL_PERIOD.toString());
        contractState.append("|CMC:");
        contractState.append(COMMISSION_MULTIPLIER.toString());
        return contractState.toString();
    }

}
