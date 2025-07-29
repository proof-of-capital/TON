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

// This is the third version of the contract. It introduces the following features: the ability to choose any jetton as support, build support with an offset,
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
const FIVE_HUNDREDTHS_TON: Int = ton("0.05"); // minimum TON amount for covering fees
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
    jettonMasterAddress: Address; // Address of the jetton master contract, used to obtain the wallet address of the main jetton
    returnWalletAddress: Address; // Return wallet address, which can return tokens to the contract and receive support from lower levels
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
    contractSupportBalance: Int as coins; // Balance of support (backing) jettons
    contractJettonBalance: Int as coins; // Balance of the contract's main jetton
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

    contractJettonWalletAddress: Address; // Wallet address of the contract's main jetton
    // Variables for withdrawing third-party jettons that may accidentally be sent to the contract
    additionalJettonWalletAddress: Address; // Wallet address of the contract's additional jetton

    // Variables for offset accounting. Used to launch the contract when some jettons are missing at deployment.
    offsetJettons: Int as coins; // Offset in jettons, used for calculating the offset
    offsetStep: Int as coins; // Current offset step
    offsetPrice: Int as coins; // Price at the current offset step
    remainderOffsetJettons: Int as coins; // Remaining jettons at the current offset step
    sizeOffsetStep: Int as coins; // Current size of the offset step

    callJettonsID: Int as uint8; // Call counter for the initial deposit (1 – first deposit, 0 – all subsequent ones)

    // New support
    jettonSupport: Bool; // Jetton support flag. If False — support is provided in TON.
    jettonSupportMasterAddress: Address; // Master contract address of the support jetton
    contractJettonSupportWalletAddress: Address; // Contract's support jetton wallet address

    // Storage of additional market maker addresses
    marketMakerAddressesMap: map<Address, Int as uint8>; // Map of market maker addresses
    marketMakerAddressesLength: Int as uint8; // Number of market makers in the map

    // Profit withdrawal
    ownerTonBalance: Int as coins; // Owner's profit in TON
    royaltyTonBalance: Int as coins; // Royalty profit in TON
    ownerSupportBalance: Int as coins; // Owner's profit in support jettons
    royaltySupportBalance: Int as coins; // Royalty profit in support jettons
    profitInTime: Bool; // Flag indicating whether profit is withdrawn immediately or upon request (true – on request, false – immediately)
    royaltyProfitPercent: Int as uint16; // Royalty profit percentage (from 1 (0.1 %) to MAX_PERCENT (100 %))
    creatorProfitPercent: Int as uint16; // Owner profit percentage (from 1 (0.1 %) to MAX_PERCENT (100 %))
    coefficientProfit: Int as uint16; // Coefficient for calculating the profit percentage (from 1 (100 %) to MAX_PERCENT (10000 %))


    canWithdrawal: Bool = true; // Flag indicating whether early delayed withdrawal is allowed (true – allowed, false – prohibited)

    // Deferred withdrawal
    mainJettonDeferredWithdrawalDate: Int as uint64 = 0; // End date of deferred withdrawal for the main jetton
    mainJettonDeferredWithdrawalAmount: Int as coins = 0; // Amount of the main jetton for deferred withdrawal
    recipientDeferredWithdrawalMainJetton: Address; // Recipient address for the deferred withdrawal of the main jetton

    supportJettonDeferredWithdrawalDate: Int as uint64 = 0; // End date of the waiting period for delayed withdrawal of the support token
    recipientDeferredWithdrawalSupportJetton: Address; // Recipient address for the deferred withdrawal of the support jetton
    jettonDecimals: Int as uint32; // Number of decimals for the jetton
    farm: Address; // Farm address

    isInitialized: Bool = false; // Flag indicating whether the contract's jetton wallets are initialized (required to run self.calculateOffset())

    init(id: Int,
        owner: Address,
        marketMakerAddress: Address,
        jettonMasterAddress: Address,
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
        jettonSupport: Bool,
        jettonSupportMasterAddress: Address,
        royaltyProfitPercent: Int,
        coefficientProfit: Int,
        jettonDecimals: Int
        ) {
        self.oldContractAddress = owner;
        self.oldContractAddressesMap = emptyMap();
        self.oldContractAddressesLength = 0;

        self.id = 0;
        self.owner = owner;
        self.jettonMasterAddress = jettonMasterAddress;
        self.contractJettonWalletAddress = owner;
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
        self.jettonSupport = jettonSupport;
        self.jettonSupportMasterAddress = jettonSupportMasterAddress;
        self.contractJettonSupportWalletAddress = owner;
        self.jettonDecimals = jettonDecimals;
        self.currentStep = 0;
        self.remainderOfStep = firstLevelJettonQuantity;
        self.contractJettonBalance = 0;
        self.jettonsEarned = 0;
        self.queryId = 0;
        self.contractSupportBalance = 0;
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
        self.callJettonsID = 1;

        self.reserveOwner = owner;

        self.marketMakerAddressesMap = emptyMap();
        self.marketMakerAddressesLength = 1;
        self.marketMakerAddressesMap.set(marketMakerAddress, self.marketMakerAddressesLength);

        self.ownerTonBalance = 0;
        self.royaltyTonBalance = 0;
        self.ownerSupportBalance = 0;
        self.royaltySupportBalance = 0;
        self.profitInTime = true;

        self.royaltyProfitPercent = royaltyProfitPercent;
        self.creatorProfitPercent = MAX_PERCENT - royaltyProfitPercent;

        self.recipientDeferredWithdrawalMainJetton = owner;
        self.recipientDeferredWithdrawalSupportJetton = owner;

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
            to: self.jettonMasterAddress,
            value: 0,
            mode: SendRemainingValue,
            body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: false}.toCell()
        });
    }

    // Receives and sends messages to jetton master contracts, stores the addresses of the main and support jetton wallets.
    // Change flag isInitialized after all jetton wallets received.
    // Triggers the offset calculation function.
    receive(msg: TakeWalletAddress) {
        require(sender() == self.jettonMasterAddress || sender() == self.jettonSupportMasterAddress, "Invalid main or support jetton master sender");
        require(!self.isInitialized, "Contract jetton wallets are already initialized");
        if (sender() == self.jettonMasterAddress) {
            self.contractJettonWalletAddress = msg.wallet_address;
            if (self.jettonSupport) {
                message(MessageParameters{
                    to: self.jettonSupportMasterAddress,
                    value: 0,
                    mode: SendRemainingValue,
                    body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: true}.toCell()
                });
            } else {
                self.calculateOffset(self.offsetJettons);
                self.isInitialized = true;
            }
        } else {
            self.contractJettonSupportWalletAddress = msg.wallet_address;
        }
        if (self.contractJettonWalletAddress != self.owner && self.contractJettonSupportWalletAddress != self.owner) {
            self.calculateOffset(self.offsetJettons);
            self.isInitialized = true;
        }
    }

    // Extends the lock for a specified period at the request of the owner. Supported durations are 10 minutes, 3 months, or 6 months.
    receive(msg: ExtendLock) {
        require(sender() == self.owner, "Access is only for the owner");
        require(context().value > self.commission, "Amount must be greater than commission");
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


    // Schedules a deferred withdrawal of the main jetton in 30 days to the specified address.
    receive(msg: JettonDeferredWithdrawal) {
        require(sender() == self.owner, "Access is only for the owner");
        require(msg.amount > 0 && msg.recipientAddress != newAddress(0, 0), "Recipient address and jetton amount cannot be zero");
        require(self.canWithdrawal, "Deferred withdrawal is blocked");
        require(self.mainJettonDeferredWithdrawalAmount == 0, "Main jetton deferred withdrawal is already scheduled");
        self.recipientDeferredWithdrawalMainJetton = msg.recipientAddress;
        self.mainJettonDeferredWithdrawalDate = now() + THIRTY_DAYS;
        self.mainJettonDeferredWithdrawalAmount = msg.amount;
        message(MessageParameters{
            to: msg.recipientAddress,
            value: self.commission,
            bounce: true,
            mode: SendPayFwdFeesSeparately,
            body: "Requested withdrawal of main jettons to recipient of current transaction after 30 days".asComment()
        });
    }

    // Cancels the delayed withdrawal of the main token and resets the associated data. It can be used by both the creator and the royalty wallet.
    receive(msg: StopJettonDeferredWithdrawal) {
        require(sender() == self.owner || sender() == self.royaltyWalletAddress || sender() == self.farm, "Access is only for the owner or royaltyWallet or farm");
        require(self.mainJettonDeferredWithdrawalDate != 0, "Main jetton deferred withdrawal date is not set");
        self.mainJettonDeferredWithdrawalDate = 0;
        self.mainJettonDeferredWithdrawalAmount = 0;
        self.recipientDeferredWithdrawalMainJetton = self.owner;
        self.notify("Main jetton deferred withdrawal stopped and date reset".asComment());
    }

    // Confirms and executes the deferred withdrawal of main jettons after the waiting period expires.
    receive(msg: ConfirmJettonDeferredWithdrawal) {
        require(sender() == self.owner, "Access is only for the owner");
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        require(self.canWithdrawal, "Deferred withdrawal is blocked");
        require(self.mainJettonDeferredWithdrawalDate != 0, "Main jetton deferred withdrawal date is not set or reset");
        require(now() >= self.mainJettonDeferredWithdrawalDate, "Main jetton deferred withdrawal date is not arrived yet");
        require(now() <= self.mainJettonDeferredWithdrawalDate + SEVEN_DAYS, "Main jetton deferred withdrawal period is finished");

        let amount: Int = min(self.mainJettonDeferredWithdrawalAmount, self.contractJettonBalance - self.totalJettonsSold);
        if (amount > 0) {
            self.transferTokensToWithPayload(self.contractJettonWalletAddress, self.recipientDeferredWithdrawalMainJetton, amount, MainJettonDeferredWithdrawal{}.toCell(), self.commission * 2, self.commission );
        }
        
        self.contractJettonBalance -= amount;
        self.mainJettonDeferredWithdrawalDate = 0;
        self.mainJettonDeferredWithdrawalAmount = 0;
        self.recipientDeferredWithdrawalMainJetton = self.owner;
    }

    // Schedules a deferred withdrawal of the support jettons in 30 days to the specified address.
    receive(msg: SupportDeferredWithdrawal) {
        require(sender() == self.owner, "Access is only for the owner");
        require(self.canWithdrawal, "Deferred withdrawal is blocked");
        require(msg.recipientAddress != newAddress(0, 0), "Recipient address cannot be null");
        require(self.supportJettonDeferredWithdrawalDate == 0, "Support jetton deferred withdrawal is already scheduled");
        self.recipientDeferredWithdrawalSupportJetton = msg.recipientAddress;
        self.supportJettonDeferredWithdrawalDate = now() + THIRTY_DAYS;
        message(MessageParameters{
            to: msg.recipientAddress,
            value: self.commission,
            bounce: true,
            mode: SendPayFwdFeesSeparately,
            body: "Requested withdrawal of support jettons to recipient of current transaction after 30 days".asComment()
        });
    }

    // Cancels the deferred withdrawal of support jettons and resets the related data. Can be called by either the creator or the royalty wallet.
    receive(msg: StopSupportDeferredWithdrawal) {
        require(sender() == self.owner || sender() == self.royaltyWalletAddress || sender() == self.farm, "Access is only for the owner or royaltyWallet or farm");
        require(self.supportJettonDeferredWithdrawalDate != 0, "Support jetton deferred withdrawal date is not set");
        self.supportJettonDeferredWithdrawalDate = 0;
        self.recipientDeferredWithdrawalSupportJetton = self.owner;
        self.notify("Support jetton deferred withdrawal stopped and date reset".asComment());
    }

    // Confirms and executes the deferred withdrawal of support jettons after the waiting period expires.
    receive(msg: ConfirmSupportDeferredWithdrawal) {
        require(sender() == self.owner, "Access is only for the owner");
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        require(self.canWithdrawal, "Deferred withdrawal is blocked");
        require(self.supportJettonDeferredWithdrawalDate != 0, "Support jetton deferred withdrawal date is not set or reset");
        require(now() >= self.supportJettonDeferredWithdrawalDate, "Support jetton deferred withdrawal date is not arrived yet");
        require(now() <= self.supportJettonDeferredWithdrawalDate + SEVEN_DAYS, "Support jetton deferred withdrawal period is finished");

        if (self.jettonSupport) {
            self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, self.recipientDeferredWithdrawalSupportJetton, self.contractSupportBalance, SupportJettonDeferredWithdrawal{}.toCell(), self.commission * 2, self.commission);
        } else {
            message(MessageParameters{
                to: self.recipientDeferredWithdrawalSupportJetton,
                value: self.contractSupportBalance,
                bounce: true,
                mode: SendPayFwdFeesSeparately,
                body: "Support jetton deferred withdrawal".asComment()
            });
        }

        self.contractSupportBalance = 0;
        self.supportJettonDeferredWithdrawalDate = 0;
        self.recipientDeferredWithdrawalSupportJetton = self.owner;
        self.isActive = false;
    }

    // Assigns a new main owner. Only the current the reserve owner can perform this action.
    // If the current owner is the the reserve owner, both addresses are updated to the new owner.
    receive(msg: AssignNewOwner) {
        require(sender() == self.owner || sender() == self.reserveOwner, "Only the owner or the reserve owner can make changes.");
        require(msg.newOwner != newAddress(0, 0), "New owner address cannot be null.");
        require((!self.oldContractAddressesMap.exists(msg.newOwner)), "Old contract address cannot be equal to any of addresses in contract");
        if (self.owner == self.reserveOwner) {
            self.owner = msg.newOwner;
            self.reserveOwner = msg.newOwner;
        } else {
            self.owner = msg.newOwner;
        }
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
        require(sender() == self.owner, "Access is only for the owner");
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        require(msg.newAdditionalJettonWalletAddress != self.contractJettonSupportWalletAddress, "Additional jetton wallet address in mesage cannot be support jetton wallet");
        require(msg.newAdditionalJettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address in mesage cannot be zero");
        self.additionalJettonWalletAddress = msg.newAdditionalJettonWalletAddress;
        self.transferTokensToWithPayload(self.additionalJettonWalletAddress, self.owner, msg.amount, SendOtherJettonsToOwner{}.toCell(), self.commission * 2, self.commission);
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
            msg.oldContractAddress != self.jettonMasterAddress &&
            msg.oldContractAddress != self.contractJettonWalletAddress &&
            msg.oldContractAddress != self.additionalJettonWalletAddress &&
            msg.oldContractAddress != self.jettonSupportMasterAddress &&
            msg.oldContractAddress != self.contractJettonSupportWalletAddress &&
            msg.oldContractAddress != self.returnWalletAddress &&
            msg.oldContractAddress != self.royaltyWalletAddress &&
            msg.oldContractAddress != self.recipientDeferredWithdrawalMainJetton &&
            msg.oldContractAddress != self.recipientDeferredWithdrawalSupportJetton &&
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
    // The logic depends on the support mode (self.jettonSupport) and the sender's address:
    // - If support with jettons is enabled and the call comes from the owner or the old contract (oldContractAddress),
    //   it confirms that support is active (to protect from inconsistent calls), and ensures the contract is active and jetton wallets are initialized.
    // - If support with jettons is disabled, calls from the owner or old contract can adjust the support balance
    //   if there is a jetton offset, reducing the supportBalance debt.
    // - For other calls (e.g., trades from MarketMaker or whitelisted addresses), the following checks apply:
    //   lockEndTime restriction, verification of sender permissions in marketMakerAddressesMap,
    //   and control of fees and balances.
    // - Also includes logic to return change (excess funds) to the owner.
    //
    // Calculates the amount of main jettons to issue for the received funds (after deducting fees),
    // distributes the profit between the creator and the royalty wallet, and depending on the profit payout mode,
    // either immediately transfers the profit or accumulates it for later withdrawal.
    // Then updates the contract balance and sends jettons to the sender.

    receive() {
        if (self.jettonSupport && (sender() == self.owner || sender() == self.oldContractAddress)) {
            require(self.jettonSupport, "Jetton support is not used.");
        } else {
            require(self.isInitialized, "Contract jetton wallets are not initialized yet");
            require(!self.jettonSupport, "Jetton support is used");
            let value = context().value;
            if (self.profitInTime) {
                value -= self.commission * 4;
            } else {
                value -= self.commission * 2;
            }
            if (sender() == self.owner || sender() == self.oldContractAddress) {
                if (self.offsetJettons - self.jettonsEarned > 0)
                {
                    let deltaSupportBalance = self.calculateChangeOffsetSupport(value);
                    self.contractSupportBalance += deltaSupportBalance;
                    let change = value - deltaSupportBalance;
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

                let totalTokens: Int = self.calculateJettonsToGiveForSupportAmount(value);
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

                self.contractSupportBalance += netValue;
                self.totalJettonsSold += totalTokens;

                self.transferTokensToWithPayload(self.contractJettonWalletAddress, sender(), totalTokens, PurchaseIsSuccess{}.toCell(), self.commission * 2, self.commission );

                self.queryId += 1;
            }
        }
    }

    // Handler for incoming JettonTransferNotification messages.
    //
    // Executes logic based on the notification sender and the contract state.
    //
    // Main scenarios:
    // 1. If the notification comes from the support jetton wallet (contractJettonSupportWalletAddress):
    //    - Ensures support mode is active and the sender address is valid.
    //    - If the transfer is from the owner or oldContractAddress:
    //      - If a positive offset in support jettons exists, the support balance is increased and the support jettons are accounted for.
    //    - Otherwise:
    //      - Verifies the sender is an authorized MarketMaker (depending on lock period or unlock window).
    //      - Updates the control day if needed.
    //      - Checks fee payment and sufficient support jetton balance.
    //      - Calculates the number of main jettons to issue, distributes profit to creator and royalty.
    //      - Updates the support balance and total sold jettons.
    //      - Sends main jettons to the sender.
    //      - Updates the total support jetton amount.
    //
    // 2. If the notification comes from the main jetton wallet (contractJettonWalletAddress):
    //    - Ensures consistency of jetton states (earned and offset).
    //    - If the transfer is from the owner or oldContractAddress:
    //      - Depending on the internal counter, updates the main jetton balance or triggers offset recalculation.
    //    - If the transfer is from returnWalletAddress (buyback):
    //      - Checks commission sufficiency.
    //      - Calculates the support amount to be paid based on the amount of jettons being bought back and current offset.
    //      - Updates support and main jetton balances.
    //      - If required, sends funds to the owner's address (via TON or jetton transfer).
    //    - Otherwise:
    //      - Checks MarketMaker permissions or unlock window conditions.
    //      - Verifies sufficient funds for jetton buyback.
    //      - Calculates the amount of support jettons to return and updates support and sold jetton balances.
    //      - Sends funds back to the user (via TON or jetton, depending on the support mode).
    //      - Updates the total amount of support jettons.
    //
    // Always checks that the contract is active and initialized, otherwise throws an error.
    // If any error occurs (while the contract is active and initialized), the transferred jettons are refunded to the sender with a specified reason.
    receive(msg: JettonTransferNotification) {
        let value = context().value;
        require(self.isInitialized, "Contract jetton wallets are not initialized yet");
        require(self.isActive, "Contract is not active");
        if (sender() == self.contractJettonSupportWalletAddress) {
            try {
                require(self.jettonSupport, "Jettons support is not used or notification not from your jetton support wallet!");
                if (self.profitInTime) {
                    require(value >= self.commission * 4, "Insufficient funds to cover commission for transfer support jettons.");
                } else {
                    require(value >= self.commission * 2, "Insufficient funds to cover commission for transfer support jettons.");
                }
                if (msg.sender == self.owner || msg.sender == self.oldContractAddress) {
                    if (self.offsetJettons - self.jettonsEarned > 0) {
                        let deltaSupportBalance = self.calculateChangeOffsetSupport(msg.amount);
                        self.contractSupportBalance += deltaSupportBalance;
                        let change = msg.amount - deltaSupportBalance;
                        if (change > 0) {
                            self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, self.owner, change, SendChangeToOwner{}.toCell(), self.commission * 2, self.commission);
                        }
                    } else {
                        self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, self.owner, value, SendBackToOwner{}.toCell(), self.commission * 2, self.commission);
                    }
                } else {
                    if (!self.checkTradingAccess()) {
                        if (self.checkUnlockWindow()) {
                            self.controlDay += THIRTY_DAYS * self.calculatePastPeriods();
                        }
                        require(self.marketMakerAddressesMap.exists(msg.sender), "Now can trade only MarketMaker and this address is not a MarketMaker");
                    }
                    require(self.contractJettonBalance > self.totalJettonsSold, "Insufficient jetton balance.");

                    let totalTokens: Int = self.calculateJettonsToGiveForSupportAmount(msg.amount);
                    let creatorProfit: Int = self.actualProfit * self.creatorProfitPercent / MAX_PERCENT;
                    let royaltyProfit: Int = self.actualProfit * self.royaltyProfitPercent / MAX_PERCENT;
                    let netValue: Int = msg.amount - self.actualProfit;

                    if (self.profitInTime) {
                        self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, self.owner, creatorProfit, SendProfitToOwner{}.toCell(), self.commission, self.commission / 5);
                        self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, self.royaltyWalletAddress, royaltyProfit, SendProfitToRoyalty{}.toCell(), self.commission, self.commission / 5);
                    } else {
                        self.ownerSupportBalance += creatorProfit;
                        self.royaltySupportBalance += royaltyProfit;
                    }

                    self.contractSupportBalance += netValue;
                    self.totalJettonsSold += totalTokens;
                    self.transferTokensToWithPayload(self.contractJettonWalletAddress, msg.sender, totalTokens, PurchaseIsSuccess{}.toCell(), self.commission * 2, self.commission );

                }
            } catch (error) {
                let errorComment: StringBuilder = beginString();
                errorComment.append("Something went wrong (");
                errorComment.append(error.toString());
                errorComment.append(")");
                self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, msg.sender, msg.amount, errorComment.toCell(), self.commission * 2, self.commission);
            }
        } else {
            try {
                require(sender() == self.contractJettonWalletAddress, "Notification not from your jetton wallet!");
                if (msg.sender == self.owner || msg.sender == self.oldContractAddress) {
                    if (self.callJettonsID == 1) {
                        self.contractJettonBalance += msg.amount;
                        self.callJettonsID = 0;
                    } else {
                        if (self.totalJettonsSold == self.offsetJettons && (self.offsetJettons - self.jettonsEarned) >= msg.amount) {
                            // @misti:suppress UnusedExpressionResult
                            self.calculateChangeOffsetJetton(msg.amount);
                        } else {
                            self.contractJettonBalance += msg.amount;
                        }
                    }
                } else if (msg.sender == self.returnWalletAddress) {
                    require(value >= self.commission, "Amount must be greater than 0.05");
                    let amount: Int = msg.amount;
                    let supportAmountToPay: Int = 0;
                    let tokensAvailableForReturnBuyback: Int = self.totalJettonsSold - self.jettonsEarned;
                    let effectiveAmount: Int = min(amount, tokensAvailableForReturnBuyback);

                    if (self.offsetJettons > self.jettonsEarned) {
                        if (effectiveAmount > self.offsetJettons - self.jettonsEarned) {
                            // @misti:suppress UnusedExpressionResult
                            self.calculateSupportForTokenAmountEarned(self.offsetJettons - self.jettonsEarned);
                            let buybackAmount: Int = effectiveAmount - (self.offsetJettons - self.jettonsEarned);
                            supportAmountToPay = self.calculateSupportForTokenAmountEarned(buybackAmount);
                        } else {
                            // @misti:suppress UnusedExpressionResult
                            self.calculateSupportForTokenAmountEarned(effectiveAmount);
                            supportAmountToPay = 0;
                        }
                    } else {
                        supportAmountToPay = self.calculateSupportForTokenAmountEarned(effectiveAmount);
                    }

                    self.jettonsEarned += effectiveAmount;
                    require(self.contractSupportBalance >= supportAmountToPay, "Insufficient contract balance for redemption");
                    self.contractSupportBalance -= supportAmountToPay;
                    self.contractJettonBalance += amount;

                    if (supportAmountToPay > 0) {
                        if (self.jettonSupport) {
                            self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, self.farm, supportAmountToPay, PriceGrowthBuyback{}.toCell(), self.commission * 2, self.commission);
                        } else {
                            message(MessageParameters{
                                to: self.farm,
                                value: supportAmountToPay,
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
                    require(value > self.commission, "Amount must be greater than minimal");
                    let tokensAvailableForBuyback: Int = self.totalJettonsSold - max(self.offsetJettons, self.jettonsEarned);
                    let tokenForBuyback: Int = msg.amount;
                    require(tokensAvailableForBuyback > 0, "Not have tokensAvailableForBuyback");
                    require(tokensAvailableForBuyback >= tokenForBuyback, "Insufficient tokens available for buyback");
                    let supportAmountToPay: Int = self.calculateSupportToPayForTokenAmount(tokenForBuyback);

                    require(self.contractSupportBalance >= supportAmountToPay, "Not enough support balance");

                    self.contractSupportBalance -= supportAmountToPay;
                    self.totalJettonsSold -= tokenForBuyback;

                    if (self.jettonSupport) {
                        self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, msg.sender, supportAmountToPay, SupportBuyback{}.toCell(), self.commission * 2, self.commission);
                    } else {
                        message(MessageParameters{
                            to: msg.sender,
                            value: supportAmountToPay,
                            bounce: true,
                            mode: SendPayFwdFeesSeparately,
                            body: "Support Buyback".asComment()
                        });
                    }
                }
            } catch(error) {
                let errorComment: StringBuilder = beginString();
                errorComment.append("Something went wrong (");
                errorComment.append(error.toString());
                errorComment.append(")");
                self.transferTokensToWithPayload(self.contractJettonWalletAddress, msg.sender, msg.amount, errorComment.toCell(), self.commission * 2, self.commission);
            }
        }
    }


    receive(msg: SetFarm) {
        require(sender() == self.owner, "Access is only for the owner");
        require(self.farm == self.owner, "Farm already set");
        self.farm = msg.farm;
    }

    // Transfers all unsold jettons to the owner after the lock period ends.
    // Verifies caller's permission and lock time.
    // Resets the contract state to initial parameters.
    receive(msg: WithdrawAllCoins) {
        require(sender() == self.farm, "Access is only for the farm");
        require(now() >= self.lockEndTime, "Lock period has not ended yet!");
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        self.transferTokensToWithPayload(self.contractJettonWalletAddress, self.farm, self.contractJettonBalance - self.totalJettonsSold, TransferAllMainJettonsToOwner{}.toCell(), self.commission * 2, self.commission); // todo fix farm
        self.contractJettonBalance = 0;
        self.isActive = false;
    }

    // Transfers the entire support jetton balance to the owner after the lock period ends.
    // Verifies caller's permission, lock time, and support mode.
    // Resets the support balance after the transfer.
    receive(msg: WithdrawAllSupportCoins) {
        require(sender() == self.farm, "Access is only for the farm");
        require(now() >= self.lockEndTime, "Lock period has not ended yet!");
        require(context().value >= self.commission * 2, "Insufficient funds to cover commission for transfer profit");
        require(self.jettonSupport, "Jetton support is not used.");
        self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, self.farm, self.contractSupportBalance, SendAllSupportBalanceToOwner{}.toCell(), self.commission * 2, self.commission); // todo fix farm
        self.contractSupportBalance = 0;
        self.isActive = false;
    }

    // Transfers the entire available TON balance to the owner after the lock period ends.
    // Verifies caller's permission and lock time.
    // Resets the support balance and updates the TON balance used for fees.
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
        self.contractSupportBalance = 0;
        self.isActive = false;
    }

    // Sends unused TON to the owner.
    // Takes into account the support mode and deducts the fee.
    receive(msg: WithdrawUnusedTons) {
        require(sender() == self.owner, "Access is only for the owner");
        let unusedTonToWithdraw: Int = 0;
        if (self.jettonSupport) {
            unusedTonToWithdraw = myBalance() - (self.commission * COMMISSION_MULTIPLIER);
        } else {
            unusedTonToWithdraw = myBalance() - self.contractSupportBalance - self.ownerTonBalance - self.royaltyTonBalance - (self.commission * COMMISSION_MULTIPLIER);
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
            if (self.jettonSupport) {
                self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, sender(), self.ownerSupportBalance, SendProfitToOwner{}.toCell(), self.commission * 2, self.commission );
                self.ownerSupportBalance = 0;
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
            if (self.jettonSupport) {
                self.transferTokensToWithPayload(self.contractJettonSupportWalletAddress, sender(), self.royaltySupportBalance, SendProfitToRoyalty{}.toCell(), self.commission * 2, self.commission);
                self.royaltySupportBalance = 0;
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
            body: GetLockEndTime{ queryId: msg.queryId, originalGasTo: msg.originalGasTo, lockEndTime: self.lockEndTime, mainJettonDeferredWTHDate: self.mainJettonDeferredWithdrawalDate, supportJettonDeferredWTHDate: self.supportJettonDeferredWithdrawalDate }.toCell()});
    }

    // Sends the current price of the main jetton to the sender.
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
    // jetton support , launch token, active, current price
    receive(msg: FetchContractInfoAfterUpdatePoc) {
        require(context().value >= self.commission, "Insufficient funds to cover commission for transfer jetton support");
        message(MessageParameters{
            to: sender(),
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: GetContractInfoAfterUpdatePoc{ queryId: msg.queryId, originalGasTo: msg.originalGasTo, jettonSupportAddress: self.jettonSupportMasterAddress, jettonLaunchAddress: self.jettonMasterAddress, isActive: self.isActive, currentPrice: self.currentPrice }.toCell()});
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
        return (self.mainJettonDeferredWithdrawalDate > 0) || (self.supportJettonDeferredWithdrawalDate > 0) || self.lockEndTime - SIXTY_DAYS < now() || self.checkControlDay();
    }

    // Helper function to check if the current time is within the "unlock window" period after the lock expires.
    fun checkUnlockWindow(): Bool {
        return (now() - self.controlDay - THIRTY_DAYS > self.controlPeriod);
    }

    // Sends the specified amount of jettons with a comment to the given address.
    fun transferTokensToWithPayload(toAddress: Address, recipient: Address, amount: Int, payload: Cell, value: Int, forwardTonAmount: Int) {
        message(MessageParameters{
            to: toAddress,
            value: value,
            mode: SendPayFwdFeesSeparately,
            body: JettonTransfer{
                queryId: self.queryId,
                amount: amount,
                destination: recipient,
                responseDestination: recipient,
                customPayload: null,
                forwardTonAmount: forwardTonAmount,
                forwardPayload: payload.asSlice(),
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

    // Calculates the offset change for support based on the given support amount,
    // updating the internal offset and step state.
    //
    // Logic:
    // - Iterates over the remaining support amount and available offset tokens.
    // - For each step, calculates the available number of tokens, profit percentage, and actual support cost.
    // - If the remaining support and tokens cover the entire step, decreases the remainder and step count,
    //   adjusts step parameters and price.
    // - If the support is less than the full step cost, distributes tokens partially and updates remainders.
    // - Updates the current step, price, and offset remainder parameters.
    //
    // Returns:
    // - The amount of support successfully distributed across steps.
    fun calculateChangeOffsetSupport(amountSupport: Int): Int {
        let remainingAddSupport: Int = amountSupport;
        let remainingOffsetJettons: Int = self.offsetJettons;
        let remainingAddJettons: Int = self.offsetJettons - self.jettonsEarned;
        let localCurrentStep: Int = self.offsetStep;
        let remainderOfStep: Int = self.remainderOffsetJettons;
        let jettonsPerLevel: Int = self.sizeOffsetStep;
        let currentPrice: Int = self.offsetPrice;

        while (remainingAddSupport > 0 && remainingAddJettons > 0) {
            let tokensAvailableInStep: Int = jettonsPerLevel - remainderOfStep;
            let profitPercentage: Int = self.calculateProfit(localCurrentStep);
            let tonInStep: Int = tokensAvailableInStep * currentPrice / self.jettonDecimals;
            let tonRealInStep: Int = tonInStep * (MAX_PERCENT - profitPercentage) / MAX_PERCENT;

            if (remainingAddSupport >= tonRealInStep && remainingAddJettons >= tokensAvailableInStep) {
                remainingAddSupport -= tonRealInStep;
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

                let supportToPayForStep: Int = 0;
                let tokensToBuyInThisStep: Int = 0;


                if (remainingAddSupport >= tonRealInStep) {
                    supportToPayForStep = remainingAddJettons * adjustedPrice / self.jettonDecimals;
                    tokensToBuyInThisStep = remainingAddJettons;
                } else {
                    supportToPayForStep = remainingAddSupport;
                    tokensToBuyInThisStep = remainingAddSupport * self.jettonDecimals / adjustedPrice;
                }
                remainderOfStep += tokensToBuyInThisStep;
                remainingAddSupport -= supportToPayForStep;
                remainingOffsetJettons -= tokensToBuyInThisStep;
                remainingAddJettons = 0;
            }
        }

        self.offsetStep = localCurrentStep;
        self.remainderOffsetJettons = remainderOfStep;
        self.offsetPrice = currentPrice;
        self.sizeOffsetStep = jettonsPerLevel;
        self.offsetJettons = remainingOffsetJettons;

        return (amountSupport - remainingAddSupport);
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

    // Calculates the number of tokens to be issued for a given support amount.
    //
    // Logic:
    // - Initializes local variables for the current step, remainder, tokens per level, and price.
    // - In a loop, while there is remaining support and tokens available to issue:
    //   - Determines the available number of tokens at the current step and the required TON amount to purchase them.
    //   - If the support is sufficient for a full step:
    //     - Increases the number of tokens to issue by the full step amount.
    //     - Calculates and accumulates profit for that step.
    //     - Moves to the next step, recalculating tokens per level and price.
    //   - If the support is insufficient for a full step:
    //     - Calculates how many tokens can be bought with the remaining support.
    //     - Adds them to the total number to be issued.
    //     - Calculates and adds profit for this partial step.
    //     - Sets the remaining support to zero and adjusts the step remainder.
    // - If more tokens are requested than available, limits issuance to the maximum remaining.
    // - Updates offset state, current step, price, and profit.
    //
    // Returns:
    // - The number of tokens to be issued.
    fun calculateJettonsToGiveForSupportAmount(supportAmount: Int): Int {
        let jettonsToGive: Int = 0;
        let remainingSupportAmount: Int = supportAmount;
        let localCurrentStep: Int = self.currentStep;
        let remainderOfStep: Int = self.remainderOfStep;
        let jettonsPerLevel: Int = self.quantityJettonsPerLevel;
        let currentPrice: Int = self.currentPrice;
        let totalProfit: Int = 0;
        let remainderOfjettons: Int = self.contractJettonBalance - self.totalJettonsSold;

        while (remainingSupportAmount > 0 && remainderOfjettons >= jettonsToGive) {
            let tokensAvailableInStep: Int = remainderOfStep;
            let tonRequiredForStep: Int = tokensAvailableInStep * currentPrice / self.jettonDecimals;

            if (remainingSupportAmount >= tonRequiredForStep) {
                jettonsToGive += tokensAvailableInStep;
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let profitInStep: Int = (tonRequiredForStep * profitPercentage) / MAX_PERCENT;

                totalProfit += profitInStep;

                remainingSupportAmount -= tonRequiredForStep;

                localCurrentStep += 1;

                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);

                remainderOfStep = jettonsPerLevel;
                currentPrice = (currentPrice * (MAX_PERCENT + self.priceIncrementMultiplier)) / MAX_PERCENT;
            } else {
                let tokensToBuyInThisStep: Int = remainingSupportAmount * self.jettonDecimals / currentPrice;
                jettonsToGive += tokensToBuyInThisStep;
                let tonSpentInThisStep: Int = remainingSupportAmount;

                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let profitInStep: Int = (tonSpentInThisStep * profitPercentage) / MAX_PERCENT;

                totalProfit += profitInStep;

                remainingSupportAmount = 0;
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

    // Calculates the support amount (supportAmountToPay) required to purchase a given number of tokens (tokenAmount).
    //
    // Logic:
    // - Uses local copies of the current step, step token remainder, price, and tokens per level.
    // - While there are tokens left to pay for:
    //   - Determines the number of tokens available at the current step.
    //   - If the remaining token amount is greater than or equal to the available tokens in the step:
    //     - Calculates the profit percentage for the current step.
    //     - Adjusts the price with the profit.
    //     - Calculates the support amount for the full step and adds it to the total payment.
    //     - Reduces the remaining token amount.
    //     - Updates level parameters and price when transitioning to a new step.
    //     - Adjusts the step and step token remainder based on the current state.
    //   - If the token amount is less than the available tokens in the step:
    //     - Calculates the support amount for the partial token quantity similarly.
    //     - Updates the step token remainder.
    //     - All tokens are paid — the loop ends.
    // - Updates the contract state: current step, tokens per level, current price, and remainder.
    //
    // Returns:
    // - The total support amount to be paid.
    fun calculateSupportToPayForTokenAmount(tokenAmount: Int): Int {
        let supportAmountToPay: Int = 0;
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
                let supportToPayForStep: Int = tokensAvailableInStep * adjustedPrice / self.jettonDecimals;
                supportAmountToPay += supportToPayForStep;

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
                let supportToPayForStep: Int = remainingJettonAmount * adjustedPrice / self.jettonDecimals;
                supportAmountToPay += supportToPayForStep;

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

        return supportAmountToPay;
    }

    // Calculates the support amount (supportAmountToPay) required to be paid for a given number of earned tokens (tokenAmount).
    //
    // Logic:
    // - Uses local copies of current step, step token remainder, price, and tokens per level for earned.
    // - While there are tokens left to pay for and the current step does not exceed the maximum step:
    //   - Determines the number of tokens available at the current step (remainder).
    //   - If the remaining token amount is greater than or equal to the available remainder:
    //     - Calculates the profit percentage for the current step.
    //     - Adjusts the price including the profit.
    //     - Calculates the support amount for the full remainder and adds it to the total payment.
    //     - Proceeds to the next step.
    //     - Updates the number of tokens per level (jettonsPerLevel) using the calculateJettonsPerLevel function.
    //     - Sets the new remainder to the updated tokens per level.
    //     - Decreases the remaining token amount.
    //     - Updates the current price using the increment multiplier.
    //   - If fewer tokens remain than available in the remainder:
    //     - Similarly calculates the support amount for the partial token quantity.
    //     - Updates the remainder by subtracting the paid tokens.
    //     - Ends the loop (all tokens are paid).
    // - After the loop, updates the contract state (current earned step, tokens per level, current price, and remainder).
    //
    // Returns:
    // - The total support amount to be paid.
    fun calculateSupportForTokenAmountEarned(tokenAmount: Int): Int {
        let supportAmountToPay: Int = 0;
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
                let supportToPayForStep: Int = tokensAvailableInStep * adjustedPrice / self.jettonDecimals;
                supportAmountToPay += supportToPayForStep;

                localCurrentStep += 1;

                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStep = jettonsPerLevel;
                remainingJettonAmount -= tokensAvailableInStep;

                currentPrice = currentPrice * (MAX_PERCENT + self.priceIncrementMultiplier) / MAX_PERCENT;
            } else {
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let adjustedPrice: Int = currentPrice * (MAX_PERCENT - profitPercentage) / MAX_PERCENT;

                let supportToPayForStep: Int = remainingJettonAmount * adjustedPrice / self.jettonDecimals;
                supportAmountToPay += supportToPayForStep;

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

        return supportAmountToPay;
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

    get fun support_token_balance(): Int {
        return self.contractSupportBalance;
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
        if (!self.jettonSupport) {
            return self.ownerTonBalance;
        } else {
            return self.ownerSupportBalance;
        }
    }

    get fun check_royalty_profit(): Int {
        if (!self.jettonSupport) {
            return self.royaltyTonBalance;
        } else {
            return self.royaltySupportBalance;
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
        return self.contractJettonWalletAddress;
    }

    get fun jetton_master_address(): Address {
        return self.jettonMasterAddress;
    }

    get fun current_step(): Int {
        return self.currentStep;
    }

    get fun step_remainder(): Int {
        return self.remainderOfStep;
    }

    get fun support_to_jetton_calculation(a: Int): Int {
        let b: Int = self.calculateJettonsToGiveForSupportAmount(a);
        return b;
    }

    get fun jetton_to_support_calculation(a: Int): Int {
        let b: Int = self.calculateSupportToPayForTokenAmount(a);
        return b;
    }

    get fun jetton_to_return_calculation(a: Int): Int {
        let b: Int = self.calculateSupportForTokenAmountEarned(a);
        return b;
    }

    get fun contract_address(): Address {
        return myAddress();
    }


    get fun additional_jetton_wallet_address(): Address {
        return self.additionalJettonWalletAddress;
    }

    get fun unused_support_ton(): Int {
        let unused_amount: Int = myBalance() - self.contractSupportBalance - (self.commission * COMMISSION_MULTIPLIER);
        return unused_amount;
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

    get fun calculate_change_offset_support(a: Int): Int {
        let b: Int = self.calculateChangeOffsetSupport(a);
        return b;
    }

    get fun calculate_change_offset_jetton(a: Int): Int {
        let b: Int = self.calculateChangeOffsetJetton(a);
        return b;
    }

    get fun is_jetton_support(): Bool {
        return self.jettonSupport;
    }

    get fun jetton_support_master_address(): Address {
        return self.jettonSupportMasterAddress;
    }

    get fun contract_jetton_support_wallet_address(): Address {
        return self.contractJettonSupportWalletAddress;
    }

    get fun royalty_profit_percent(): Int {
        return self.royaltyProfitPercent;
    }

    get fun creator_profit_percent(): Int {
        return self.creatorProfitPercent;
    }

    get fun main_jetton_deferred_WTH_Date(): Int {
        return self.mainJettonDeferredWithdrawalDate;
    }

    get fun main_jetton_deferred_WTH_Recipient(): Address {
        return self.recipientDeferredWithdrawalMainJetton;
    }

    get fun main_jetton_deferred_WTH_Amount(): Int {
        return self.mainJettonDeferredWithdrawalAmount;
    }

    get fun support_jetton_deferred_WTH_Date(): Int {
        return self.supportJettonDeferredWithdrawalDate;
    }

    get fun support_jetton_deferred_WTH_Recipient(): Address {
        return self.recipientDeferredWithdrawalSupportJetton;
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

    get fun support_tokens_contract_values(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("JSMA:");
        contractState.append(self.jettonSupportMasterAddress.toString());
        contractState.append("|CJSWA:");
        contractState.append(self.contractJettonSupportWalletAddress.toString());
        contractState.append("|CSB:");
        contractState.append(self.contractSupportBalance.toCoinsString());
        return contractState.toString();
    }

    get fun standard_contract_state_support_values(): String {
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
        contractState.append(self.contractSupportBalance.toCoinsString());
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
        contractState.append(self.mainJettonDeferredWithdrawalDate.toString());
        contractState.append("|MJDWA:");
        contractState.append(self.mainJettonDeferredWithdrawalAmount.toCoinsString());
        contractState.append("|SJDD:");
        contractState.append(self.supportJettonDeferredWithdrawalDate.toString());
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
