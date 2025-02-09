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
const TEN_MINUTES: Int = 600;
const FIVE_HUNDREDTHS_TON: Int = ton("0.05");
const COMMISSION_MULTIPLIER: Int = 10;

contract ProofOfCapital with Deployable, OwnableTransferable {
    id: Int as uint256;
    owner: Address;
    jettonMasterAddress: Address;
    marketMakerAddress: Address;
    returnWalletAddress: Address;
    royaltyWalletAddress: Address;
    lockEndTime: Int as uint64;
    initialPricePerToken: Int as coins;
    firstLevelJettonQuantity: Int as coins;
    priceIncrementMultiplier: Int as uint16;
    commission: Int as coins;

    levelIncreaseMultiplier: Int as uint16;
    trendChangeStep: Int as uint8;
    levelDecreaseMultiplierafterTrend: Int as uint16;
    profitPercentage: Int as uint16;
    queryId: Int as uint64;
    totalJettonsSold: Int as coins;
    contractTonBalance: Int as coins;
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
        ) {
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

        self.currentStep = 0;
        self.remainderOfStep = firstLevelJettonQuantity;
        self.contractJettonBalance = 0;
        self.jettonsEarned = 0;
        self.queryId = 0;
        self.contractTonBalance = 0;
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
        require(ctx.sender == self.jettonMasterAddress, "Invalid sender");
        self.contractJettonWalletAddress = msg.wallet_address;
    }


    receive(msg: ExtendLock) {
        self.requireOwner();
        require(context().value > self.commission, "Amount must be greater than 0.05");
        let newLockEndTime = self.lockEndTime + msg.additionalTime;
        require(newLockEndTime - now() < TWO_YEARS, "Lock end time cannot exceed two years");
        require(msg.additionalTime == HALF_YEAR || msg.additionalTime == TEN_MINUTES || msg.additionalTime == THREE_MONTHS, "Invalid time!");
        self.lockEndTime = newLockEndTime;

        if (msg.additionalTime == HALF_YEAR) {
            send(SendParameters{
                to: self.owner,
                value: 0,
                bounce: true,
                mode: SendPayGasSeparately,
                body: "Lock extended for 182 days.".asComment()
            });
        } else if (msg.additionalTime == TEN_MINUTES) {
            send(SendParameters{
                to: self.owner,
                value: 0,
                bounce: true,
                mode: SendPayGasSeparately,
                body: "Lock extended for 10 minutes.".asComment()
            });
        } else {
            send(SendParameters{
                to: self.owner,
                value: 0,
                bounce: true,
                mode: SendPayGasSeparately,
                body: "Lock extended for 3 months.".asComment()
            });
        }
    }

    receive(msg: ChangeCommissionValue) {
        self.requireOwner();
        require(msg.commissionValue >= FIVE_HUNDREDTHS_TON, "Amount must be greater than 0.05");
        self.commission = msg.commissionValue;
    }

    receive(msg: ChangeMarketMaker) {
        self.requireOwner();
        self.marketMakerAddress = msg.newMarketMakerAddress;
    }

    receive(msg: ChangeReturnWallet) {
        self.requireOwner();
        self.returnWalletAddress = msg.newReturnWalletAddress;
    }

    receive(msg: ChangeRoyaltyWallet) {
        require(sender() == self.royaltyWalletAddress, "Access is only for royalty.");
        self.royaltyWalletAddress = msg.newRoyaltyWalletAddress;
    }

    receive(msg: AddAdditionalJettonData) {
        self.requireOwner();
        require(msg.newAdditionalJettonMasterAddress != newAddress(0, 0), "Additional jetton master address in message cannot be zero");
        require(msg.newAdditionalJettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address in mesage cannot be zero");
        require(self.additionalJettonMasterAddress != newAddress(0, 0), "Additional jetton master address cannot be zero");
        require(self.additionalJettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address cannot be zero");
        require(msg.newAdditionalJettonMasterAddress != self.jettonMasterAddress && msg.newAdditionalJettonWalletAddress != self.contractJettonWalletAddress, "Additional addresses match addresses of the main jetton!");
        self.additionalJettonMasterAddress = msg.newAdditionalJettonMasterAddress;
        self.additionalJettonWalletAddress = msg.newAdditionalJettonWalletAddress;
        self.transferAdditionalTokensTo(msg.amount);
        self.queryId += 1;
    }

    receive() {
        let value = context().value - self.commission * 2;
        if (sender() == self.owner){
            self.contractTonBalance = self.contractTonBalance + context().value;
        } else {
            if (self.lockEndTime - now() > SIXTY_DAYS) {
                require(sender() == self.marketMakerAddress, "Now can trade only MarketMaker");
            }
            require(value >= self.commission, "Insufficient funds to cover commission");


            let totalTokens: Int = self.calculateJettonsToGiveForTonAmount(value);
            let creatorProfit: Int = self.actualProfit * 8 / 10;
            let royaltyProfit: Int = self.actualProfit * 2 / 10;
            let netValue: Int = value - self.actualProfit;

            self.contractTonBalance += netValue;
            self.totalJettonsSold += totalTokens;

            send(SendParameters{
                to: self.owner,
                value: creatorProfit,
                bounce: true,
                mode: SendPayGasSeparately,
                body: "Development and Marketing Fund".asComment()
            });

            send(SendParameters{
                to: self.royaltyWalletAddress,
                value: royaltyProfit,
                bounce: true,
                mode: SendPayGasSeparately,
                body: "Royalty".asComment()
            });

            self.transferTokensTo(sender(), totalTokens);
            self.queryId = self.queryId + 1;
        }
    }

    receive(msg: JettonTransferNotification) {
        let value = context().value;
        require(
            sender() == self.contractJettonWalletAddress,
            "Notification not from your jetton wallet!",
        );
        require(
            self.jettonsEarned <= self.totalJettonsSold,
            "Earned jettons are more than sold!",
        );
        if (msg.sender == self.owner) {
            self.contractJettonBalance = self.contractJettonBalance + msg.amount;
        } else if (msg.sender == self.returnWalletAddress) {
            require(value > self.commission, "Amount must be greater than 0.05");
            let amount: Int = msg.amount;
            let tokensAvailableForReturnBuyback: Int = self.totalJettonsSold - self.jettonsEarned;
            let effectiveAmount: Int = min(amount, tokensAvailableForReturnBuyback);
            let tonToPay: Int = self.calculateTonForTokenAmountEarned(effectiveAmount);
            self.jettonsEarned = self.jettonsEarned + effectiveAmount;

            if (self.contractTonBalance - tonToPay) < 0 {
                self.contractTonBalance = 0;
            } else {
                self.contractTonBalance = self.contractTonBalance - tonToPay;
            }
            self.contractJettonBalance = self.contractJettonBalance + amount;

            require(tonToPay > 0, "Amount tonToPay must be greater than 0");
            send(SendParameters{
                to: self.owner,
                value: tonToPay,
                bounce: true,
                mode: SendPayGasSeparately,
                body: "Price Growth Buyback".asComment()
            });
        } else {
            if (self.lockEndTime - now() > SIXTY_DAYS) {
                require(msg.sender == self.marketMakerAddress, "Now can trade only MarketMaker");
            }
            require(value > self.commission, "Amount must be greater than 0.05");
            let tokensAvailableForBuyback: Int = self.totalJettonsSold - self.jettonsEarned;
            let tokenForBuyback: Int = msg.amount;
            require(tokensAvailableForBuyback > 0, "Not have tokensAvailableForBuyback");
            require(tokensAvailableForBuyback < tokenForBuyback, "Insufficient tokens available for buyback");
            let tonToPay: Int = self.calculateTonToPayForTokenAmount(tokenForBuyback);

            if (self.contractTonBalance - tonToPay < 0) {
                self.contractTonBalance = 0;
            } else {
                self.contractTonBalance = self.contractTonBalance - tonToPay;
            }
            if (self.totalJettonsSold - tokenForBuyback < 0) {
                self.totalJettonsSold = 0;
            } else {
                self.totalJettonsSold = self.totalJettonsSold - tokenForBuyback;
            }

            send(SendParameters{
                to: msg.sender,
                value: tonToPay,
                bounce: true,
                mode: SendPayGasSeparately,
                body: "Support Buyback".asComment()
            });
        }
    }

    receive(msg: WithdrawAllCoins) {
        self.requireOwner();
        require(
            now() >= self.lockEndTime,
            "Lock period has not ended yet!",
        );
        self.transferTokensTo(sender(), self.contractJettonBalance - self.totalJettonsSold);
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

    receive(msg: WithdrawAllTons) {
        self.requireOwner();
        require(
            now() >= self.lockEndTime,
            "Lock period has not ended yet!",
        );
        let amount: Int = myBalance() - context().value - self.commission;
        send(SendParameters{
            to: self.owner,
            value: amount,
            mode: SendIgnoreErrors | SendRemainingValue,
            bounce: true,
            body: "Send all balance to owner".asComment()
        });
        self.contractTonBalance = 0;
    }

    receive(msg: WithdrawUnusedTons) {
        self.requireOwner();
        let unusedTonToWithdraw: Int = myBalance() - self.contractTonBalance - (self.commission * COMMISSION_MULTIPLIER);
        send(SendParameters{
            to: self.owner,
            value: unusedTonToWithdraw,
            mode: SendPayGasSeparately | SendBounceIfActionFail,
            bounce: true,
            body: "Send unused tons to owner".asComment()
        });
    }

    fun transferAdditionalTokensTo(amount: Int) {
        send(SendParameters{
            to: self.additionalJettonWalletAddress,
            value: self.commission,
            body: JettonTransfer{
                queryId: self.queryId,
                amount: amount,
                destination: self.owner,
                responseDestination: self.owner,
                customPayload: null,
                forwardTonAmount: 1,
                forwardPayload: rawSlice("4_")
            }.toCell(),
        });
    }

    fun transferTokensTo(recipient: Address, amount: Int) {
        send(SendParameters{
            to: self.contractJettonWalletAddress,
            value: self.commission,
            body: JettonTransfer{
                queryId: self.queryId,
                amount: amount,
                destination: recipient,
                responseDestination: recipient,
                customPayload: null,
                forwardTonAmount: 1,
                forwardPayload: rawSlice("4_")
            }.toCell(),
        });
    }

    fun calculateProfit(currentStep: Int): Int {
        if (currentStep > self.trendChangeStep) {
            return self.profitPercentage;
        } else {
            return self.profitPercentage * 2;
        }
    }

    fun calculateJettonsPerLevel(jettonsPerLevel: Int, currentStep: Int): Int {
        if (currentStep > self.trendChangeStep) {
            return (jettonsPerLevel *
            (1000 - self.levelDecreaseMultiplierafterTrend)) / 1000;
        } else {
            return (jettonsPerLevel * (1000 + self.levelIncreaseMultiplier)) / 1000;
        }
    }

    fun calculateJettonsToGiveForTonAmount(tonAmount: Int): Int {
        let jettonsToGive: Int = 0;
        let remainingTonAmount: Int = tonAmount;
        let localCurrentStep: Int = self.currentStep;
        let remainderOfStep: Int = self.remainderOfStep;
        let jettonsPerLevel: Int = self.quantityJettonsPerLevel;
        let currentPrice: Int = self.currentPrice;
        let totalProfit: Int = 0;
        let remainderOfjettons: Int = self.contractJettonBalance - self.totalJettonsSold;

        while (remainingTonAmount > 0 && remainderOfjettons >= jettonsToGive) {
            let tokensAvailableInStep: Int = remainderOfStep;
            let tonRequiredForStep: Int = tokensAvailableInStep * currentPrice / 1000000000;

            if (remainingTonAmount >= tonRequiredForStep) {
                jettonsToGive += tokensAvailableInStep;
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let profitInStep: Int = (tonRequiredForStep * profitPercentage) / 1000;

                totalProfit += profitInStep;

                remainingTonAmount -= tonRequiredForStep;

                localCurrentStep += 1;

                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);

                remainderOfStep = jettonsPerLevel;
                currentPrice = (currentPrice * (1000 + self.priceIncrementMultiplier)) / 1000;
            } else {
                let tokensToBuyInThisStep: Int = remainingTonAmount * 1000000000 / currentPrice;
                jettonsToGive += tokensToBuyInThisStep;
                let tonSpentInThisStep: Int = remainingTonAmount;

                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let profitInStep: Int = (tonSpentInThisStep * profitPercentage) / 1000;

                totalProfit += profitInStep;

                remainingTonAmount = 0;
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


    fun calculateTonToPayForTokenAmount(tokenAmount: Int): Int {
        let tonToPay: Int = 0;
        let remainingJettonAmount: Int = tokenAmount;
        let localCurrentStep: Int = self.currentStep;
        let remainderOfStep: Int = self.remainderOfStep;
        let jettonsPerLevel: Int = self.quantityJettonsPerLevel;
        let currentPrice: Int = self.currentPrice;

        while (remainingJettonAmount > 0) {
            let tokensAvailableInStep: Int = jettonsPerLevel - remainderOfStep;

            if (remainingJettonAmount >= tokensAvailableInStep) {
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);


                let adjustedPrice: Int = currentPrice * (1000 - profitPercentage) / 1000;
                let tonToPayForStep: Int = tokensAvailableInStep * adjustedPrice / 1000000000;
                tonToPay += tonToPayForStep;

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
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let adjustedPrice: Int = currentPrice * (1000 - profitPercentage) / 1000;
                let tonToPayForStep: Int = remainingJettonAmount * adjustedPrice / 1000000000;
                tonToPay += tonToPayForStep;

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

        return tonToPay;
    }

    fun calculateTonForTokenAmountEarned(tokenAmount: Int): Int {
        let tonToPay: Int = 0;
        let remainingJettonAmount: Int = tokenAmount;
        let localCurrentStep: Int = self.currentStepEarned;
        let remainderOfStep: Int = self.remainderOfStepEarned;
        let jettonsPerLevel: Int = self.quantityJettonsPerLevelEarned;
        let currentPrice: Int = self.currentPriceEarned;

        while (remainingJettonAmount > 0 && localCurrentStep <= self.currentStep) {
            let tokensAvailableInStep: Int = remainderOfStep;

            if (remainingJettonAmount >= tokensAvailableInStep) {
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let adjustedPrice: Int = currentPrice * (1000 - profitPercentage) / 1000;
                let tonToPayForStep: Int = tokensAvailableInStep * adjustedPrice / 1000000000;
                tonToPay += tonToPayForStep;

                localCurrentStep += 1;

                jettonsPerLevel = self.calculateJettonsPerLevel(jettonsPerLevel, localCurrentStep);
                remainderOfStep = jettonsPerLevel;
                remainingJettonAmount -= tokensAvailableInStep;

                currentPrice = currentPrice * (1000 + self.priceIncrementMultiplier) / 1000;
            } else {
                let profitPercentage: Int = self.calculateProfit(localCurrentStep);

                let adjustedPrice: Int = currentPrice * (1000 - profitPercentage) / 1000;

                let tonToPayForStep: Int = remainingJettonAmount * adjustedPrice / 1000000000;
                tonToPay += tonToPayForStep;

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

        return tonToPay;
    }

    get fun remaining_seconds(): Int {
        return self.lockEndTime - now();
    }

    get fun trading_opportunity(): Bool {
        return self.lockEndTime - now() < SIXTY_DAYS;
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

    get fun ton_balance(): Int {
        return self.contractTonBalance;
    }

    get fun profit(): Int {
        return self.profitPercentage;
    }

    get fun balance(): Int {
        return myBalance();
    }

    get fun market_maker_address(): Address {
        return self.marketMakerAddress;
    }

    get fun return_wallet_address(): Address {
        return self.returnWalletAddress;
    }

    get fun owner_address(): Address {
        return self.owner;
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

    get fun ton_to_jetton_calculation(a: Int): Int {
        let b: Int = self.calculateJettonsToGiveForTonAmount(a);
        return b;
    }

    get fun jetton_to_ton_calculation(a: Int): Int {
        let b: Int = self.calculateTonToPayForTokenAmount(a);
        return b;
    }

    get fun jetton_to_return_calculation(a: Int): Int {
        let b: Int = self.calculateTonForTokenAmountEarned(a);
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

    get fun unused_tons(): Int {
        let unused_amount: Int = myBalance() - self.contractTonBalance - (self.commission * COMMISSION_MULTIPLIER);
        return unused_amount;
    }

}
