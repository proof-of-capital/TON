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

// All royalties collected are automatically used to repurchase the project’s core token, as
// specified on the website, and are returned to the contract.

import "@stdlib/deploy";
import "@stdlib/ownable";
import "./message";


const TWO_YEARS: Int = 63_072_000;
const HALF_YEAR: Int = 15_768_000;
const SIXTY_DAYS: Int = 5_184_000;
const THREE_MONTHS: Int = 7_776_000; 
const MIN_CONTROL_PERIOD: Int = 21_600;
const TEN_MINUTES: Int = 600;
const FIVE_HUNDREDTHS_TON: Int = ton("0.05");
const COMMISSION_MULTIPLIER: Int = 10;
const THREE_WEEKS: Int = 1_814_000;
const THIRTY_DAYS: Int = 2_592_000;

fun checkPeriod(period: Int): Int {
    if (period < MIN_CONTROL_PERIOD) {
        period = MIN_CONTROL_PERIOD;
    } else if (period > SIXTY_DAYS) {
        period = SIXTY_DAYS;
    }
    return period;
}

contract ProofOfCapital with Deployable, OwnableTransferable {
    oldContractAddress: Address;

    id: Int as uint256;
    owner: Address;
    reserveOwner: Address;
    jettonMasterAddress: Address;
    marketMakerAddress: Address;
    returnWalletAddress: Address;
    royaltyWalletAddress: Address;
    lockEndTime: Int as uint64;
    initialPricePerToken: Int as coins;
    firstLevelJettonQuantity: Int as coins;
    priceIncrementMultiplier: Int as uint16;
    commission: Int as coins;
    controlDay: Int as uint64;
    controlPeriod: Int as uint32;

    levelIncreaseMultiplier: Int as uint16;
    trendChangeStep: Int as uint8;
    levelDecreaseMultiplierafterTrend: Int as uint16;
    profitPercentage: Int as uint16;
    queryId: Int as uint64;
    totalJettonsSold: Int as coins;
    contractSupportBalance: Int as coins;
    contractJettonBalance: Int as coins;
    jettonsEarned: Int as coins;

    quantityJettonsPerLevel: Int as coins;
    actualProfit: Int as coins;
    currentPrice: Int as coins;
    currentStep: Int as coins;
    remainderOfStep: Int as coins;
    currentStepEarned: Int as coins;
    remainderOfStepEarned: Int as coins;
    quantityJettonsPerLevelEarned: Int as coins;

    currentPriceEarned: Int as coins;
    contractJettonWalletAddress: Address;
    additionalJettonWalletAddress: Address;
    additionalJettonMasterAddress: Address;

    // новые переменные
    offsetJettons: Int as coins;
    offsetStep: Int as coins;
    offsetPrice: Int as coins;
    remainderOffsetJettons: Int as coins;
    sizeOffsetStep: Int as coins;
    callJettonsID: Int as uint8;

    switchOwner: Int as uint8;

    // новое обеспечение
    jettonSupport: Bool;
    jettonSupportMasterAddress: Address;
    contractJettonSupportWalletAddress: Address;

    contractTonForCommissionBalance: Int as coins;
    allSupportTokens: Int as coins;

    // хранение адресов
    marketMakerAddressesMap: map<Address, Int>;
    markerMakerIndex: Int as uint8;

    // вывод профитов
    ownerTonBalance: Int as coins;
    royaltyTonBalance: Int as coins;
    ownerSupportBalance: Int as coins;
    royaltySupportBalance: Int as coins;
    profitSelectorOwner: Bool;
    royaltyProfitPercent: Int as uint8; // от 1 до 10
    creatorProfitPercent: Int as uint8;

    // короткий лок для вывода USDT
    deferredLock: Int as uint64;
    recipientDeferredLock: Address;

    canWTH: Int as uint8 = 1;

    // отложенный вывод
    mainJettonDeferredWTHDate: Int as uint64 = 0;
    mainJettonDeferredWTHAmount: Int as coins = 0;
    recipientDeferredWTHMainJetton: Address;

    supportJettonDeferredWTHDate: Int as uint64 = 0;
    supportJettonDeferredWTHAmount: Int as coins = 0;
    recipientDeferredWTHSupportJetton: Address;

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
        royaltyProfitPercent: Int
        ) {
        self.oldContractAddress = owner;
        self.id = 0;
        self.owner = owner;
        self.marketMakerAddress = marketMakerAddress;
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

        self.jettonSupport = jettonSupport;
        self.jettonSupportMasterAddress = jettonSupportMasterAddress;
        self.contractJettonSupportWalletAddress = owner;

        self.currentStep = 0;
        self.remainderOfStep = firstLevelJettonQuantity;
        self.contractJettonBalance = 0;
        self.jettonsEarned = 0;
        self.queryId = 0;
        self.contractSupportBalance = 0;
        self.additionalJettonWalletAddress = owner;
        self.additionalJettonMasterAddress = owner;
        self.totalJettonsSold = 0;
        self.quantityJettonsPerLevel = firstLevelJettonQuantity;
        self.actualProfit = 0;
        self.currentPrice = initialPricePerToken;
        self.currentStepEarned = 0;
        self.remainderOfStepEarned = firstLevelJettonQuantity;
        self.quantityJettonsPerLevelEarned = firstLevelJettonQuantity;
        self.currentPriceEarned = initialPricePerToken;
        self.commission = FIVE_HUNDREDTHS_TON;
        self.controlDay = now() + SIXTY_DAYS;

        self.offsetJettons = offsetJettons;
        self.offsetStep = 0;
        self.offsetPrice = initialPricePerToken;
        self.remainderOffsetJettons = firstLevelJettonQuantity;
        self.sizeOffsetStep = firstLevelJettonQuantity;
        self.controlPeriod = checkPeriod(controlPeriod);
        self.callJettonsID = 1;

        self.reserveOwner = owner;
        self.switchOwner = 0;

        self.contractTonForCommissionBalance = 0;
        self.allSupportTokens = 0;

        self.marketMakerAddressesMap = emptyMap();
        self.markerMakerIndex = 1;
        self.marketMakerAddressesMap.set(marketMakerAddress, 1);

        self.ownerTonBalance = 0;
        self.royaltyTonBalance = 0;
        self.ownerSupportBalance = 0;
        self.royaltySupportBalance = 0;
        self.profitSelectorOwner = true;

        self.royaltyProfitPercent = royaltyProfitPercent;
        self.creatorProfitPercent = 10 - royaltyProfitPercent;

        self.deferredLock = 0;
        self.recipientDeferredLock = owner;

        self.recipientDeferredWTHMainJetton = owner;
        self.recipientDeferredWTHSupportJetton = owner;

        send(SendParameters{
            to: self.jettonMasterAddress,
            value: 0,
            mode: SendRemainingValue,
            body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: false}.toCell()
        });
    }


    receive(msg: TakeWalletAddress) {
        let ctx: Context = context();
        require(self.contractJettonWalletAddress != newAddress(0, 0), "Contract jetton wallet address cannot be zero");
        require(self.contractJettonSupportWalletAddress != newAddress(0, 0), "Contract jetton support wallet address cannot be zero");
        if (ctx.sender == self.jettonMasterAddress) {
            require(ctx.sender == self.jettonMasterAddress, "Invalid jetton master sender");
            self.contractJettonWalletAddress = msg.wallet_address;
        } else {
            require(ctx.sender == self.jettonSupportMasterAddress, "Invalid jetton support master sender");
            self.contractJettonSupportWalletAddress = msg.wallet_address;
        }
        if (self.contractJettonSupportWalletAddress != msg.wallet_address && self.jettonSupport == true)  {
            send(SendParameters{
                to: self.jettonSupportMasterAddress,
                value: 0,
                mode: SendRemainingValue,
                body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: true}.toCell()
            });
            self.calculateOffset(self.offsetJettons);        
        }
    }

    receive(msg: ExtendLock) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(context().value > self.commission, "Amount must be greater than comission");
        require(((self.lockEndTime + msg.additionalTime) - now()) < TWO_YEARS, "Lock end time cannot exceed two years");
        require(msg.additionalTime == HALF_YEAR || msg.additionalTime == TEN_MINUTES || msg.additionalTime == THREE_MONTHS, "Invalid time!");
        self.lockEndTime += msg.additionalTime;            
        if (msg.additionalTime == HALF_YEAR) {
            send(SendParameters{
                to: self.checkSwitchOwner(),
                value: 0,
                bounce: true,
                mode: SendPayFwdFeesSeparately,
                body: "Lock extended for 182 days.".asComment()
            });        
        } else if (msg.additionalTime == TEN_MINUTES) {
            send(SendParameters{
                to: self.checkSwitchOwner(),
                value: 0,
                bounce: true,
                mode: SendPayFwdFeesSeparately,
                body: "Lock extended for 10 minutes.".asComment()
            }); 
        } else {
            send(SendParameters{
                to: self.checkSwitchOwner(),
                value: 0,
                bounce: true,
                mode: SendPayFwdFeesSeparately,
                body: "Lock extended for 3 months.".asComment()
            }); 
        }
    }

    receive(msg: StartDeferredLock) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(self.jettonSupport == true, "Jetton support is not used");
        self.recipientDeferredLock = msg.recipientAddress;
        self.deferredLock = now() + THREE_WEEKS;
        send(SendParameters{
            to: self.recipientDeferredLock,
            value: 0,
            bounce: true,
            mode: SendPayFwdFeesSeparately,
            body: "Delayed withdrawal after three weeks".asComment()
        });
    }

    receive(msg: BlockSpecialWithdrawal) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(self.canWTH != 0, "Withdrawal is already blocked");
        self.canWTH = 0;
    }

    receive(msg: SpecialWithdrawal) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(self.canWTH == 1, "Special withdrawa is blocked");
        require(now() >= self.deferredLock, "Lock period has not ended yet!");
        require(self.jettonSupport == true, "Jetton support is not used");
        self.transferTokensTo(self.contractJettonSupportWalletAddress, self.recipientDeferredLock, msg.amountSupport, "Deferred support jetton transfer");
        self.transferTokensTo(self.contractJettonWalletAddress, self.recipientDeferredLock, msg.amountMainJettons, "Deferred main jetton transfer");
        let amountSupport: Int = self.allSupportTokens >= msg.amountSupport ? msg.amountSupport : self.allSupportTokens;
        let amountMainJettons: Int = self.contractJettonBalance >= msg.amountMainJettons ? msg.amountMainJettons : self.contractJettonBalance;
        self.contractSupportBalance = self.contractSupportBalance - amountSupport > 0 ? self.contractSupportBalance - amountSupport : 0;
        self.allSupportTokens -= amountSupport;
        self.contractJettonBalance -= amountMainJettons;
        self.deferredLock = 0;
    }

    receive(msg: JettonDeferredWithdrawal) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(msg.recipientAddress != newAddress(0, 0) && msg.amount > 0, "Recipient address and jetton amount cannot be zero");
        self.recipientDeferredWTHMainJetton = msg.recipientAddress;
        self.mainJettonDeferredWTHDate = now() + THIRTY_DAYS;
        self.mainJettonDeferredWTHAmount = msg.amount;
        send(SendParameters{
            to: msg.recipientAddress,
            value: self.commission,
            bounce: true,
            mode: SendPayFwdFeesSeparately,
            body: "Requested withdrawal of main jettons to recipient of current transaction after 30 days".asComment()
        });
    }

    receive(msg: StopJettonDefWTH) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(self.mainJettonDeferredWTHDate != 0, "Main jetton deferred withdrawal date is not set");
        self.mainJettonDeferredWTHDate = 0;
        self.mainJettonDeferredWTHAmount = 0;
        self.recipientDeferredWTHMainJetton = self.checkSwitchOwner();
        self.notify("Main jetton deferred withdrawal stopped and date reset".asComment());
    }

    receive(msg: ConfirmJettonDefWTH) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(self.mainJettonDeferredWTHDate != 0, "Main jetton deferred withdrawal date is not set or reset");
        require(now() >= self.mainJettonDeferredWTHDate, "Main jetton deferred withdrawal date is not arrived yet");
        self.transferTokensTo(self.contractJettonWalletAddress, self.recipientDeferredWTHMainJetton, self.mainJettonDeferredWTHAmount, "Main jetton deferred withdrawal");
        self.contractJettonBalance -= self.mainJettonDeferredWTHAmount;
        self.totalJettonsSold -= self.mainJettonDeferredWTHAmount; 
        self.mainJettonDeferredWTHDate = 0;
        self.mainJettonDeferredWTHAmount = 0;
        self.recipientDeferredWTHMainJetton = self.checkSwitchOwner();
    }

    receive(msg: SupportDeferredWithdrawal) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(msg.recipientAddress != newAddress(0, 0) && msg.amount > 0, "Recipient address and jetton amount cannot be zero");
        self.recipientDeferredWTHSupportJetton = msg.recipientAddress;
        self.supportJettonDeferredWTHDate = now() + THIRTY_DAYS;
        self.supportJettonDeferredWTHAmount = msg.amount;
        send(SendParameters{
            to: msg.recipientAddress,
            value: self.commission,
            bounce: true,
            mode: SendPayFwdFeesSeparately,
            body: "Requested withdrawal of support jettons to recipient of current transaction after 30 days".asComment()
        });
    }

    receive(msg: StopSupportDefWTH) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(self.supportJettonDeferredWTHDate != 0, "Support jetton deferred withdrawal date is not set");
        self.supportJettonDeferredWTHDate = 0;
        self.supportJettonDeferredWTHAmount = 0;
        self.recipientDeferredWTHSupportJetton = self.checkSwitchOwner();
        self.notify("Support jetton deferred withdrawal stopped and date reset".asComment());
    }

    receive(msg: ConfirmSupportDefWTH) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(self.supportJettonDeferredWTHDate != 0, "Support jetton deferred withdrawal date is not set or reset");
        require(now() >= self.supportJettonDeferredWTHDate, "Support jetton deferred withdrawal date is not arrived yet");
        self.transferTokensTo(self.contractJettonSupportWalletAddress, self.recipientDeferredWTHSupportJetton, self.supportJettonDeferredWTHAmount, "Support jetton deferred withdrawal");
        self.allSupportTokens -= self.supportJettonDeferredWTHAmount;
        self.contractSupportBalance -= self.supportJettonDeferredWTHAmount;
        self.supportJettonDeferredWTHDate = 0;
        self.supportJettonDeferredWTHAmount = 0;
        self.recipientDeferredWTHSupportJetton = self.checkSwitchOwner();
    }

    receive(msg: AssignReserveOwner) {
        require(sender() == self.reserveOwner, "Only reserve owner can make changes.");
        self.reserveOwner = msg.reserveOwner;
    }

    receive(msg: OnSwitchOwner) {
        require(sender() == self.reserveOwner, "Only reserve owner can make changes.");
        require(msg.turnOnValue == true, "Turn on value cannot be false.");
        self.switchOwner = 1;
    }

    receive(msg: SwitchSelectorProfit) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(msg.flag != self.profitSelectorOwner, "Turn on value cannot be equal");
        self.profitSelectorOwner = msg.flag;
    }

    receive(msg: ChangeCommissionValue) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(msg.commissionValue >= FIVE_HUNDREDTHS_TON && msg.commissionValue <= ton("1"), "Amount must be greater than 0.05");
        self.commission = msg.commissionValue;
    }

    receive(msg: ChangeReturnWallet) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        self.returnWalletAddress = msg.newReturnWalletAddress;
    }

    receive(msg: ChangeRoyaltyWallet) {
        require(sender() == self.royaltyWalletAddress, "Access is only for royalty.");
        self.royaltyWalletAddress = msg.newRoyaltyWalletAddress;
    }

    receive(msg: ChangeProfitPercentage) {
        require(sender() == self.checkSwitchOwner() || sender() == self.royaltyWalletAddress, "Access only for owner or royalty");
        if (sender() == self.owner) {
            require(msg.newRoyaltyProfitPercentage > self.royaltyProfitPercent, "New percentage cannot be less than current");
            self.royaltyProfitPercent = msg.newRoyaltyProfitPercentage;
            self.creatorProfitPercent = 10 - msg.newRoyaltyProfitPercentage;
        } else {
            require(msg.newRoyaltyProfitPercentage < self.royaltyProfitPercent, "New percentage cannot be more than current");
            self.royaltyProfitPercent = msg.newRoyaltyProfitPercentage;
            self.creatorProfitPercent = 10 - msg.newRoyaltyProfitPercentage;
        }
    }

    receive(msg: AddAdditionalJettonData) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(msg.newAdditionalJettonMasterAddress != self.jettonSupportMasterAddress, "Additional jetton master address in message cannot be support master jetton");
        require(msg.newAdditionalJettonWalletAddress != self.contractJettonSupportWalletAddress, "Additional jetton wallet address in mesage cannot be support jetton wallet");
        require(msg.newAdditionalJettonMasterAddress != newAddress(0, 0), "Additional jetton master address in message cannot be zero");
        require(msg.newAdditionalJettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address in mesage cannot be zero");
        require(self.additionalJettonMasterAddress != newAddress(0, 0), "Additional jetton master address cannot be zero"); 
        require(self.additionalJettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address cannot be zero");
        require(msg.newAdditionalJettonMasterAddress != self.jettonMasterAddress && msg.newAdditionalJettonWalletAddress != self.contractJettonWalletAddress, "Additional addresses match addresses of the main jetton!");
        self.additionalJettonMasterAddress = msg.newAdditionalJettonMasterAddress;
        self.additionalJettonWalletAddress = msg.newAdditionalJettonWalletAddress;
        self.transferTokensTo(self.additionalJettonWalletAddress, self.checkSwitchOwner(), msg.amount, "Send other jettons to owner");
        self.queryId += 1;
    }

    receive(msg: AddMarketMakerAddresses) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        if (self.marketMakerAddressesMap.get(msg.newMarketMakerAddresse) == null) {
            self.markerMakerIndex += 1;
            self.marketMakerAddressesMap.set(msg.newMarketMakerAddresse, self.markerMakerIndex);
        } else {
            self.notify("Market maker address already exists".asComment());
        }
    }

    receive(msg: DeleteMarketMakerAddresses) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        if (self.marketMakerAddressesMap.get(msg.delMarketMakerAddresse) == null) {
            self.notify("Market maker address does not exist".asComment());
        } else {
            self.marketMakerAddressesMap.del(msg.delMarketMakerAddresse);
            self.markerMakerIndex -= 1;
        }
    }

    receive(msg: OldContractAddress) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(msg.oldContractAddress != newAddress(0, 0), "Old contract address cannot be zero");
        require(
            msg.oldContractAddress != self.checkSwitchOwner() && 
            msg.oldContractAddress != self.marketMakerAddress &&
            msg.oldContractAddress != self.returnWalletAddress &&
            msg.oldContractAddress != self.royaltyWalletAddress &&
            msg.oldContractAddress != self.recipientDeferredLock &&
            msg.oldContractAddress != self.recipientDeferredWTHMainJetton &&
            msg.oldContractAddress != self.recipientDeferredWTHSupportJetton,
            "Old contract address cannot be equal to any of addresses in contract"
        );
    }

    receive() {
        if (self.jettonSupport == true && (sender() == self.checkSwitchOwner() || sender() == self.oldContractAddress)) {
            require(self.jettonSupport == true, "Jetton support is used."); 
        } else {
            let value = context().value - self.commission * 2;
            if (sender() == self.checkSwitchOwner() || sender() == self.oldContractAddress) {
                if (self.offsetJettons - self.jettonsEarned > 0)
                {
                    self.contractSupportBalance += self.calculateChangeOffsetSupport(value);
                }
            } else {
                if (self.lockEndTime - now() > SIXTY_DAYS && self.checkControlDay() != true) {
                    require(self.marketMakerAddressesMap.get(sender()) != null, "Now can trade only MarketMaker and this address is not a MarketMaker");
                } else if (self.checkControlDay() == true) {
                    self.controlDay = now() + SIXTY_DAYS * self.calculatePastPeriods();
                } else if (now() - self.controlDay - SIXTY_DAYS > self.controlPeriod) {
                    self.controlDay = now() + SIXTY_DAYS * self.calculatePastPeriods();
                }
                require(value >= self.commission, "Insufficient funds to cover commission");
                require(self.contractJettonBalance > self.totalJettonsSold, "Insufficient jetton balance");

                let totalTokens: Int = self.calculateJettonsToGiveForSupportAmount(value);
                let creatorProfit: Int = self.actualProfit * self.creatorProfitPercent / 10;
                let royaltyProfit: Int = self.actualProfit * self.royaltyProfitPercent / 10;

                self.ownerTonBalance += creatorProfit;
                self.royaltyTonBalance += royaltyProfit;

                let netValue: Int = value - self.actualProfit;

                self.contractSupportBalance += netValue;
                self.totalJettonsSold += totalTokens;

                self.transferTokensTo(self.contractJettonWalletAddress, sender(), totalTokens, "Transfer main jettons");
                self.queryId += 1;
            }
        }
    }

    receive(msg: JettonTransferNotification) {
        let value = context().value;
        if (sender() == self.contractJettonSupportWalletAddress) {
            try {
                require(self.jettonSupport == true && sender() == self.contractJettonSupportWalletAddress, "Jettons support is not used or notification not from your jetton support wallet!");
                let increasedCommission = value - self.commission * 2;
                if (msg.sender == self.checkSwitchOwner() || msg.sender == self.oldContractAddress) {
                    if (self.offsetJettons - self.jettonsEarned > 0) {
                        self.contractSupportBalance += self.calculateChangeOffsetSupport(msg.amount);
                        self.allSupportTokens += msg.amount; 
                    } 
                } else {
                    if ((self.lockEndTime - now() > SIXTY_DAYS && self.checkControlDay() != true) || (now() >= self.deferredLock)) {
                        require(self.marketMakerAddressesMap.get(msg.sender) != null, "Now can trade only MarketMaker and this address is not a MarketMaker");
                    } else if (self.checkControlDay() == true) {
                        self.controlDay = now() + SIXTY_DAYS * self.calculatePastPeriods();
                    } else if (now() - self.controlDay - SIXTY_DAYS > self.controlPeriod) {
                        self.controlDay = now() + SIXTY_DAYS * self.calculatePastPeriods();
                    }
                    require(value >= self.commission, "Insufficient funds to cover commission for transfer support jettons.");
                    require(self.contractJettonBalance > self.totalJettonsSold, "Insufficient jetton balance.");

                    let totalTokens: Int = self.calculateJettonsToGiveForSupportAmount(msg.amount);
                    let creatorProfit: Int = self.actualProfit * self.creatorProfitPercent / 10;
                    let royaltyProfit: Int = self.actualProfit * self.royaltyProfitPercent / 10;
                    let netValue: Int = msg.amount - self.actualProfit;

                    self.ownerSupportBalance += creatorProfit;
                    self.royaltySupportBalance += royaltyProfit;

                    self.contractSupportBalance += netValue;
                    self.totalJettonsSold += totalTokens;

                    // self.transferTokensTo(self.contractJettonSupportWalletAddress, self.checkSwitchOwner(), creatorProfit, "Development and Marketing Fund");
                    // self.transferTokensTo(self.contractJettonSupportWalletAddress, self.royaltyWalletAddress, royaltyProfit, "Royalty");

                    self.transferTokensTo(self.contractJettonWalletAddress, msg.sender, totalTokens, "Transfer main jettons");

                    self.allSupportTokens += netValue;
                }
            } catch (error) {
                let errorComment: StringBuilder = beginString();
                errorComment.append("Something went wrong (");
                errorComment.append(error.toString());
                errorComment.append(")");
                self.transferTokensTo(self.contractJettonSupportWalletAddress, msg.sender, msg.amount, errorComment.toString());
            }
        } else {
            try {
                require(sender() == self.contractJettonWalletAddress, "Notification not from your jetton wallet!"); 
                require(self.jettonsEarned <= self.totalJettonsSold, "Earned jettons are more than sold!");
                require(self.offsetJettons <= self.totalJettonsSold, "Offset jettons are more than sold!");
                if (msg.sender == self.checkSwitchOwner() || msg.sender == self.oldContractAddress) { 
                    if (self.callJettonsID == 1) {
                        self.contractJettonBalance += msg.amount;
                        self.callJettonsID += 1;
                    } else {
                        if (self.totalJettonsSold == self.offsetJettons && (self.offsetJettons - self.jettonsEarned) >= msg.amount) {
                            self.calculateChangeOffsetJetton(msg.amount); // нет подсчета главного жетона в целом (?)
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
                            self.calculateSupportForTokenAmountEarned(self.offsetJettons - self.jettonsEarned);
                            let buybackAmount: Int = effectiveAmount - (self.offsetJettons - self.jettonsEarned);
                            supportAmountToPay = self.calculateSupportForTokenAmountEarned(buybackAmount);
                        } else {
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

                    //require(supportAmountToPay > 0, "Amount supportAmountToPay must be greater than 0");
                    if (supportAmountToPay > 0) {
                        if (self.jettonSupport == false) {
                            send(SendParameters{
                                to: self.checkSwitchOwner(),
                                value: supportAmountToPay,
                                bounce: true,
                                mode: SendPayFwdFeesSeparately,
                                body: "Price Growth Buyback".asComment()
                            });
                        } else {
                            self.transferTokensTo(self.contractJettonSupportWalletAddress, self.checkSwitchOwner(), supportAmountToPay, "Price Growth Buyback");
                        }
                    }
                    self.allSupportTokens -= supportAmountToPay;
                } else {
                    if ((self.lockEndTime - now() > SIXTY_DAYS && self.checkControlDay() != true) || (now() >= self.deferredLock)) {
                        require(self.marketMakerAddressesMap.get(msg.sender) != null, "Now can trade only MarketMaker and this address is not a MarketMaker");
                    } else if (self.checkControlDay() == true) {
                        self.controlDay = now() + SIXTY_DAYS * self.calculatePastPeriods();
                    } else if (now() - self.controlDay - SIXTY_DAYS > self.controlPeriod) {
                        self.controlDay = now() + SIXTY_DAYS * self.calculatePastPeriods();
                    }
                    require(value > self.commission, "Amount must be greater than minimal");
                    let tokensAvailableForBuyback: Int = self.totalJettonsSold - max(self.offsetJettons, self.jettonsEarned);
                    let tokenForBuyback: Int = msg.amount;
                    require(tokensAvailableForBuyback > 0, "Not have tokensAvailableForBuyback");
                    require(tokensAvailableForBuyback < tokenForBuyback, "Insufficient tokens available for buyback"); 
                    let supportAmountToPay: Int = self.calculateSupportToPayForTokenAmount(tokenForBuyback);

                    if (self.contractSupportBalance - supportAmountToPay < 0) {
                        self.contractSupportBalance = 0;
                    } else {
                        self.contractSupportBalance -= supportAmountToPay;
                    }
                    if (self.totalJettonsSold - tokenForBuyback < 0) {
                        self.totalJettonsSold = 0;
                    } else {
                        self.totalJettonsSold -= tokenForBuyback;
                    }

                    if (self.jettonSupport == false) {
                        send(SendParameters{
                            to: msg.sender,
                            value: supportAmountToPay,
                            bounce: true,
                            mode: SendPayFwdFeesSeparately,
                            body: "Support Buyback".asComment()
                        });
                    } else {
                        self.transferTokensTo(self.contractJettonSupportWalletAddress, msg.sender, supportAmountToPay, "Support Buyback");
                    }
                    self.allSupportTokens -= supportAmountToPay;
                }
            } catch(error) {
                let errorComment: StringBuilder = beginString();
                errorComment.append("Something went wrong (");
                errorComment.append(error.toString());
                errorComment.append(")");
                self.transferTokensTo(self.contractJettonWalletAddress, msg.sender, msg.amount, errorComment.toString());
            }
        }
    }

    receive(msg: WithdrawAllCoins) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(now() >= self.lockEndTime, "Lock period has not ended yet!");
        self.transferTokensTo(self.contractJettonWalletAddress, sender(), self.contractJettonBalance - self.totalJettonsSold, "Transfer all main jettons to owner");
        self.currentStep = 0;
        self.contractJettonBalance = 0;
        self.totalJettonsSold = 0;
        self.jettonsEarned = 0;
        self.quantityJettonsPerLevel = self.firstLevelJettonQuantity;
        self.currentPrice = self.initialPricePerToken;
        self.remainderOfStep = self.firstLevelJettonQuantity;
        self.currentStepEarned = 0;
        self.remainderOfStepEarned = self.firstLevelJettonQuantity;
        self.quantityJettonsPerLevelEarned = self.firstLevelJettonQuantity;
        self.currentPriceEarned = self.initialPricePerToken;
    }

    receive(msg: WithdrawAllSupportCoins) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(now() >= self.lockEndTime, "Lock period has not ended yet!");
        require(self.jettonSupport == true, "Jetton support is not used.");
        self.transferTokensTo(self.contractJettonSupportWalletAddress, sender(), self.allSupportTokens, "Send all support balance to owner.");
        self.allSupportTokens = 0;
    }

    receive(msg: WithdrawAllTons) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(now() >= self.lockEndTime, "Lock period has not ended yet!");
        let amount: Int = myBalance() - context().value - self.commission;
        send(SendParameters{
            to: self.checkSwitchOwner(),
            value: amount,
            mode: SendIgnoreErrors | SendRemainingValue,
            bounce: true,
            body: "Send all balance to owner".asComment()
        });
        self.contractSupportBalance = 0;
        self.contractTonForCommissionBalance = myBalance();
    }

    receive(msg: WithdrawUnusedTons) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        let unusedTonToWithdraw: Int = 0; 
        if (self.jettonSupport == false) {
            unusedTonToWithdraw = myBalance() - self.contractSupportBalance - (self.commission * COMMISSION_MULTIPLIER);
        } else {
            unusedTonToWithdraw = myBalance() - (self.commission * COMMISSION_MULTIPLIER);
        }
        send(SendParameters{
            to: self.checkSwitchOwner(),
            value: unusedTonToWithdraw,
            mode: SendPayFwdFeesSeparately | SendBounceIfActionFail,
            bounce: true,
            body: "Send unused tons to owner".asComment()
        });
    }

    receive(msg: WithdrawUnusedSupportCoins) {
        require(sender() == self.checkSwitchOwner(), "Access is only for primary owner or reserve owner");
        require(self.jettonSupport == true, "Jetton support is used.");
        let unusedSupportToWithdraw: Int = self.allSupportTokens - self.contractSupportBalance;
        self.transferTokensTo(self.contractJettonSupportWalletAddress, sender(), unusedSupportToWithdraw, "Send unused  tokens to owner.");
    }

    receive(msg: GetProfitOnRequest) {
        require(sender() == self.checkSwitchProfit(), "Access is only for current owner or royalty wallet");
        if (self.profitSelectorOwner == true) {
            if (self.jettonSupport == false) {
                send(SendParameters{
                    to: sender(),
                    value: self.ownerTonBalance,
                    bounce: true,
                    mode: SendPayFwdFeesSeparately,
                    body: "Send profit to owner".asComment()
                });
                self.ownerTonBalance = 0;
            } else {
                self.transferTokensTo(self.contractJettonSupportWalletAddress, sender(), self.ownerSupportBalance, "Send profit to owner");
                self.ownerSupportBalance = 0;
            }
        } else {
            if (self.jettonSupport == false) {
                send(SendParameters{
                    to: sender(),
                    value: self.royaltyTonBalance,
                    bounce: true,
                    mode: SendPayFwdFeesSeparately,
                    body: "Send profit to royalty".asComment()
                });
                self.royaltyTonBalance = 0;
            } else {
                self.transferTokensTo(self.contractJettonSupportWalletAddress, sender(), self.royaltySupportBalance, "Send profit to royalty");
                self.royaltySupportBalance = 0;
            }
        }
    }

    fun checkSwitchOwner(): Address {
        if (self.switchOwner == 0) {
            return self.owner;
        } else {
            return self.reserveOwner;
        }
    }

    fun checkSwitchProfit(): Address {
        if (self.profitSelectorOwner == true) {
            return self.checkSwitchOwner();
        } else {
            return self.royaltyWalletAddress;
        }
    }

    fun calculatePastPeriods(): Int {
        return (now() - self.controlDay) / SIXTY_DAYS;
    }

    fun checkControlDay(): Bool {
        if (now() - self.controlDay > SIXTY_DAYS && (now() - self.controlDay - SIXTY_DAYS) < self.controlPeriod) {
            return true;
        } else {
            return false;
        }
    }

    fun transferTokensTo(toAddress: Address, recipient: Address, amount: Int, comment: String) {
        let textComment: StringBuilder = beginString();
        textComment.append(comment);

        let forwardPayload: Cell = beginCell()
        .storeUint(0, 32)
        .storeRef(textComment.toCell())
        .endCell();

        send(SendParameters{
            to: toAddress,
            value: self.commission,
            body: JettonTransfer{
                queryId: self.queryId,
                amount: amount,
                destination: recipient,
                responseDestination: recipient,
                customPayload: null,
                forwardTonAmount: 1,
                forwardPayload: forwardPayload
            }.toCell(),
        });
    }

    fun calculateProfit(currentStep: Int, trendChangeStep: Int): Int {
        if (currentStep > trendChangeStep) {
            return self.profitPercentage;
        } else {
            return self.profitPercentage * 2;
        }
    }

    fun calculateJettonsPerLevel(jettonsPerLevel: Int, currentStep: Int, trendChangeStep: Int): Int {
        if (currentStep > self.trendChangeStep) {
            return (jettonsPerLevel * (1000 - self.levelDecreaseMultiplierafterTrend)) / 1000;
        } else {
            return (jettonsPerLevel * (1000 + self.levelIncreaseMultiplier)) / 1000;
        }
    }

    fun calculateOffset(amountJettons: Int): Int {
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

                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep, self.trendChangeStep);
                remainderOfStep = jettonsPerLevel;
                currentPrice = (currentPrice * (1000 + self.priceIncrementMultiplier)) / 1000;
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
        return 0;
    }
    

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
            let profitPercentage: Int = self.calculateProfit(localCurrentStep, self.trendChangeStep);
            let tonInStep: Int = tokensAvailableInStep * currentPrice / 1000000000;
            let tonRealInStep: Int = tonInStep * (1000 - profitPercentage) / 1000;

            if (remainingAddSupport >= tonRealInStep && remainingAddJettons >= tokensAvailableInStep) {
                remainingAddSupport -= tonRealInStep;
                remainingOffsetJettons -= tokensAvailableInStep;
                remainingAddJettons -= tokensAvailableInStep;

                if (localCurrentStep > self.currentStepEarned) {
                    if (localCurrentStep > self.trendChangeStep) {
                        jettonsPerLevel = jettonsPerLevel * 1000 / (1000 - self.levelDecreaseMultiplierafterTrend);
                    } else {
                        jettonsPerLevel = jettonsPerLevel * 1000 / (1000 + self.levelIncreaseMultiplier);
                    }
                    currentPrice = currentPrice * 1000 / (1000 + self.priceIncrementMultiplier);
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
                let adjustedPrice: Int = currentPrice * (1000 - profitPercentage) / 1000;

                let supportToPayForStep: Int = 0;
                let tokensToBuyInThisStep: Int = 0;

                
                if (remainingAddSupport >= tonRealInStep) {
                    supportToPayForStep = remainingAddJettons * adjustedPrice / 1000000000;
                    tokensToBuyInThisStep = remainingAddJettons;
                } else {
                    supportToPayForStep = remainingAddSupport;
                    tokensToBuyInThisStep = remainingAddSupport * 1000000000 / adjustedPrice; 
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
                        jettonsPerLevel = jettonsPerLevel * 1000 / (1000 - self.levelDecreaseMultiplierafterTrend);
                    } else {
                        jettonsPerLevel = jettonsPerLevel * 1000 / (1000 + self.levelIncreaseMultiplier);
                    }
                    currentPrice = currentPrice * 1000 / (1000 + self.priceIncrementMultiplier);
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
            let tonRequiredForStep: Int = tokensAvailableInStep * currentPrice / 1000000000;

            if (remainingSupportAmount >= tonRequiredForStep) {
                jettonsToGive += tokensAvailableInStep;
                let profitPercentage: Int = self.calculateProfit(localCurrentStep, self.trendChangeStep);

                let profitInStep: Int = (tonRequiredForStep * profitPercentage) / 1000;

                totalProfit += profitInStep;

                remainingSupportAmount -= tonRequiredForStep;

                localCurrentStep += 1;
                
                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep, self.trendChangeStep);

                remainderOfStep = jettonsPerLevel;
                currentPrice = (currentPrice * (1000 + self.priceIncrementMultiplier)) / 1000;
            } else {
                let tokensToBuyInThisStep: Int = remainingSupportAmount * 1000000000 / currentPrice;
                jettonsToGive += tokensToBuyInThisStep;
                let tonSpentInThisStep: Int = remainingSupportAmount;

                let profitPercentage: Int = self.calculateProfit(localCurrentStep, self.trendChangeStep);

                let profitInStep: Int = (tonSpentInThisStep * profitPercentage) / 1000;

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
                let profitPercentage: Int = self.calculateProfit(localCurrentStep, self.trendChangeStep);


                let adjustedPrice: Int = currentPrice * (1000 - profitPercentage) / 1000;
                let supportToPayForStep: Int = tokensAvailableInStep * adjustedPrice / 1000000000;
                supportAmountToPay += supportToPayForStep;

                remainingJettonAmount -= tokensAvailableInStep;
                
                if (localCurrentStep > self.currentStepEarned) {
                    if (localCurrentStep > self.trendChangeStep) {
                        jettonsPerLevel = jettonsPerLevel * 1000 / (1000 - self.levelDecreaseMultiplierafterTrend);
                    } else {
                        jettonsPerLevel = jettonsPerLevel * 1000 / (1000 + self.levelIncreaseMultiplier);
                    }
                    currentPrice = currentPrice * 1000 / (1000 + self.priceIncrementMultiplier);
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
                let profitPercentage: Int = self.calculateProfit(localCurrentStep, self.trendChangeStep);

                let adjustedPrice: Int = currentPrice * (1000 - profitPercentage) / 1000;
                let supportToPayForStep: Int = remainingJettonAmount * adjustedPrice / 1000000000;
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
                let profitPercentage: Int = self.calculateProfit(localCurrentStep, self.trendChangeStep);

                let adjustedPrice: Int = currentPrice * (1000 - profitPercentage) / 1000;
                let supportToPayForStep: Int = tokensAvailableInStep * adjustedPrice / 1000000000;
                supportAmountToPay += supportToPayForStep;

                localCurrentStep += 1;

                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep, self.trendChangeStep);
                remainderOfStep = jettonsPerLevel;
                remainingJettonAmount -= tokensAvailableInStep;

                currentPrice = currentPrice * (1000 + self.priceIncrementMultiplier) / 1000;
            } else {
                let profitPercentage: Int = self.calculateProfit(localCurrentStep, self.trendChangeStep);

                let adjustedPrice: Int = currentPrice * (1000 - profitPercentage) / 1000;

                let supportToPayForStep: Int = remainingJettonAmount * adjustedPrice / 1000000000;
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

    get fun check_market_maker_address(address: Address): String {
        if (self.marketMakerAddressesMap.get(address) == null) {
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

    get fun date_deferred_withdrawal(): Int {
        return self.deferredLock;
    }

    get fun recipient_deferred_withdrawal(): Address {
        return self.recipientDeferredLock;
    }

    get fun check_switch_profit(): Bool {
        return self.profitSelectorOwner;
    }

    get fun check_owner_profit(): Int {
        if (self.jettonSupport == false) {
            return self.ownerTonBalance;
        } else {
            return self.ownerSupportBalance;
        }
    }

    get fun check_royalty_profit(): Int {
        if (self.jettonSupport == false) {
            return self.royaltyTonBalance;
        } else {
            return self.royaltySupportBalance;
        }
    }

    get fun check_quantity_market_makers(): Int {
        return self.markerMakerIndex;
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

    get fun check_switch_owner(): Bool {
        return self.checkSwitchOwner() == self.owner;
    }

    get fun check_switch_value(): Int {
        return self.switchOwner;
    }

    get fun jetton_wallet_address(): Address {
        return self.contractJettonWalletAddress;
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

    get fun additional_jetton_master_address(): Address {
        return self.additionalJettonMasterAddress;
    }

    get fun additional_jetton_wallet_address(): Address {
        return self.additionalJettonWalletAddress;
    }

    get fun unused_support_ton(): Int {
        let unused_amount: Int = myBalance() - self.contractSupportBalance - (self.commission * COMMISSION_MULTIPLIER);
        return unused_amount;
    }

    get fun unused_support_tokens(): Int {
        let unused_amount: Int = self.allSupportTokens - self.contractSupportBalance;
        return unused_amount;
    }

    get fun control_day(): Int {
        return self.controlDay;
    }

    get fun control_period(): Int {
        return self.controlPeriod;
    }

    get fun current_comission(): Int {
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

    get fun calculate_offset(a: Int): Int { 
        let b: Int = self.calculateOffset(a);
        return b;
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

    get fun contract_ton_for_commission_balance(): Int {
        return self.contractTonForCommissionBalance;
    }

    get fun all_support_tokens(): Int {
        return self.allSupportTokens;
    }

    get fun royalty_profit_percent(): Int {
        return self.royaltyProfitPercent;
    }

    get fun creator_profit_percent(): Int {
        return self.creatorProfitPercent;
    }

    get fun main_jetton_deffered_WTH_Date(): Int {
        return self.mainJettonDeferredWTHDate;
    }

    get fun main_jetton_deffered_WTH_Recipient(): Address {
        return self.recipientDeferredWTHMainJetton;
    }

    get fun main_jetton_deffered_WTH_Amount(): Int {
        return self.mainJettonDeferredWTHAmount;
    }

    get fun support_jetton_deffered_WTH_Date(): Int {
        return self.supportJettonDeferredWTHDate;
    }

    get fun support_jetton_deffered_WTH_Recipient(): Address {
        return self.recipientDeferredWTHSupportJetton;
    }

    get fun support_jetton_deffered_WTH_Amount(): Int {
        return self.supportJettonDeferredWTHAmount;
    }

    get fun old_contract_address(): Address {
        return self.oldContractAddress;
    }

    get fun dates_contract_state(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("LED:");
        contractState.append(self.lockEndTime.toString());
        contractState.append("|CD:");
        contractState.append(self.controlDay.toString());
        contractState.append("|CP:");
        contractState.append(self.controlPeriod.toString());
        contractState.append("|DL:");
        contractState.append(self.deferredLock.toString());
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
        contractState.append("|CTFCB:");
        contractState.append(self.contractTonForCommissionBalance.toCoinsString());
        contractState.append("|AST:");
        contractState.append(self.allSupportTokens.toCoinsString());
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
        contractState.append(self.markerMakerIndex.toString());
        contractState.append("|SO:");
        contractState.append(self.switchOwner.toString());
        contractState.append("|CW:");
        contractState.append(self.canWTH.toString());
        return contractState.toString();
    }

    get fun contract_wth_state_values(): String {
        let contractState: StringBuilder = beginString();
        contractState.append("MJDWD:");
        contractState.append(self.mainJettonDeferredWTHDate.toString());
        contractState.append("|MJDWA:");
        contractState.append(self.mainJettonDeferredWTHAmount.toCoinsString());
        contractState.append("|SJDD:");
        contractState.append(self.supportJettonDeferredWTHDate.toString());
        contractState.append("|SJDWA:");
        contractState.append(self.supportJettonDeferredWTHAmount.toCoinsString());
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
        contractState.append(SIXTY_DAYS.toString());
        contractState.append("|MCP:");
        contractState.append(MIN_CONTROL_PERIOD.toString());
        contractState.append("|CMC:");
        contractState.append(COMMISSION_MULTIPLIER.toString());
        contractState.append("|TW:");
        contractState.append(THREE_WEEKS.toString());
        return contractState.toString();
    }

}

