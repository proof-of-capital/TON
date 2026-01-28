import "@stdlib/deploy";
import "./messages";
const COMMISSION: Int = ton("0.05"); // 0.05 TON
const MAX_PERCENT: Int = 1000; // Maximum percentage value (1000 = 100%, 10 = 1%, 1 = 0.1%)

//1. Add a POC using the AddPoc message, which sends FetchContractInfoAfterUpdatePoc to the POC (DAO)
//2. Get the token wallet address for the collateral from the added POC using the GetContractInfoAfterUpdatePoc message
//   which sends ProvideWalletAddress to the collateral master and to the launch master if it was not obtained earlier, sets settings for the POC (lock, collateral)
//3. Set the share for the POC using the SetPocSharePercentage message
//4. Send collateral to the POC contracts using the TransferCollateralToPok message
//5. Send launch tokens to itself to determine the balance of launch tokens using the LaunchSelfSend message (MM)
//6. Sends launch tokens to the POC contracts in the specified proportion using the SendLaunchTokensToPok message (MM)
//7. Request lock data from the POC using the GetPocLockDate message
// Withdraw random tokens that have arrived to us using the WithdrawAdditionalJettons message

message(0x1) AddPoc {
    queryId: Int as uint64;
    originalGasTo: Address;
    pokAddress: Address;
}

message(0x2) LaunchSelfSend {
    jettonMasterAddress: Address;
    amount: Int as coins;
}

message(0x3) TransferCollateralToPok {
    pokAddress: Address;
    amount: Int as coins;
}

message(0x4) SetPocSharePercentage {
    pokAddress: Address;
    sharePercentage: Int as uint16;
}

message(0x5) SendLaunchTokensToPok {
    pokAddress: Address;
    amount: Int as coins;
}

message(0x6) WithdrawEarning {
    pokAddress: Address;
}

message(0x7) WithdrawAdditionalJettons {
    jettonWalletAddress: Address;
    amount: Int as coins;
}

message(0x8) ChangeOwner {
    newOwner: Address;
}

message(0x9) ChangeMarketMaker {
    newMarketMaker: Address;
}

message(0xa) SetRoyaltyWalletAddress {
    newRoyaltyWalletAddress: Address;
}

message(0xb) UpdateRoyaltyWalletOnPoc {
    pokAddress: Address;
}

message(0xc) BlockDeferredWithdrawalOnPoc {
    pokAddress: Address;
    isForJetton: Bool; // true - for jetton, false - for collateral
}

contract ReturnWallet with Deployable {
    owner: Address;
    dao: Address;
    marketMaker: Address;

    launchJettonMasterAddress: Address;
    launchJettonWalletAddress: Address = newAddress(0, 0);
    launchJettonBalance: Int as coins = 0;

    collateralAllowedAddresses: map<Address, Bool>; // Map of collateral allowed addresses (k - address, v - is allowed)
    collateralWalletAddresses: map<Address, Address>; // Map of collateral jetton wallet addresses (k - master wallet, v - RW wallet address  )
    
    pokActiveStatuses: map<Address, Bool>; // Map of pok addresses (k - pok address, v - is active)
    pokCollateralAddresses: map<Address, Address>; // Map of pok addresses (k - pok address, v - collateral jetton master address)
    pokSharePercentages: map<Address, Int as uint16>; // Map of pok addresses (k - pok address, v - share percentage)
    pokCount: Int as uint8 = 0;

    newRoyaltyWalletAddress: Address = newAddress(0, 0);

    init(launchJettonMasterAddress: Address, marketMaker: Address){
        self.owner = sender();
        self.dao = sender();
        self.marketMaker = marketMaker;
        self.launchJettonMasterAddress = launchJettonMasterAddress;
    }


    receive(msg: AddPoc){
        require(context().value > COMMISSION *3, "Not enought fee");
        require(sender() == self.dao, "Access is only for the dao");
        require(msg.pokAddress != newAddress(0, 0), "Pok address cannot be null");
        require(!self.pokActiveStatuses.exists(msg.pokAddress), "Pok already exists");
        self.pokActiveStatuses.set(msg.pokAddress, false);
        reserveAtMost(context().value);
        message(MessageParameters{
            to: msg.pokAddress,
            value: 0,
            mode: SendRemainingBalance | SendIgnoreErrors,
            body: FetchContractInfoAfterUpdatePoc{queryId: now(), originalGasTo: msg.originalGasTo}.toCell()
        });
    }

    receive(msg: GetContractInfoAfterUpdatePoc){
        require(self.pokActiveStatuses.exists(sender()), "Invalid sender");
        self.pokActiveStatuses.set(sender(), msg.isActive);
        self.pokCollateralAddresses.set(sender(), msg.jettonCollateralAddress);
        self.collateralAllowedAddresses.set(msg.jettonCollateralAddress, true);
        self.pokCount+=1;
        if(msg.jettonCollateralAddress != newAddress(0, 0)){
            message(MessageParameters{
                to: msg.jettonCollateralAddress,
                value: COMMISSION,
                mode: SendDefaultMode,
                body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: false}.toCell()
            });        
        }
        if(self.launchJettonWalletAddress == newAddress(0, 0)){
            message(MessageParameters{
                to: msg.jettonLaunchAddress,
                value: COMMISSION,
                mode: SendDefaultMode,
                body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: false}.toCell()
            });            
        }
    }

    receive(msg: TakeWalletAddress) {
        require(sender() == self.launchJettonMasterAddress || self.collateralAllowedAddresses.exists(sender()), "Only from allowed masters");
        if (sender() == self.launchJettonMasterAddress) {
            self.launchJettonWalletAddress = msg.wallet_address;
        } else {
            self.collateralWalletAddresses.set(sender(), msg.wallet_address);
        }
    }

    receive(msg: SetPocSharePercentage){
        require(sender() == self.dao, "Access is only for the dao");
        require(msg.sharePercentage <= MAX_PERCENT, "Share percentage must be between 1 and 1000");
        let usedPercents = 0;
        foreach(pok, percents in self.pokSharePercentages){
            usedPercents += percents;
        }
        require(usedPercents + msg.sharePercentage <= MAX_PERCENT, "Total share percentage cannot be greater than 100%");
        self.pokSharePercentages.set(msg.pokAddress, msg.sharePercentage);
    }


    receive(msg: TransferCollateralToPok){
        require(msg.amount > 0, "Amount must be greater than 0");
        require(self.pokCollateralAddresses.exists(msg.pokAddress), "POC is not found");
        let collateralMasterAddress = self.pokCollateralAddresses.get(msg.pokAddress)!!;
        if(collateralMasterAddress == newAddress(0, 0)){
            require(myBalance() + COMMISSION * 10 > msg.amount, "Not enought balance");
            require(msg.amount > COMMISSION * 10, "Amount too low");
            message(MessageParameters{
                to: msg.pokAddress,
                value: msg.amount,
                mode: SendPayFwdFeesSeparately | SendIgnoreErrors,
                body: null
            });
        }else{
            require(context().value >= COMMISSION * 4, "Insufficient funds to cover commission");
            require(self.collateralWalletAddresses.exists(collateralMasterAddress), "Collateral wallet address is not found");
            transferTokensTo(self.collateralWalletAddresses.get(collateralMasterAddress)!!, msg.pokAddress, msg.amount, COMMISSION * 4, COMMISSION * 3);
        }
    }

    receive(msg: LaunchSelfSend){
        require(context().value >= COMMISSION * 3, "Insufficient funds to cover commission");
        require(sender() == self.marketMaker, "Access is only for the market maker");
        transferTokensTo(self.launchJettonWalletAddress, self.launchJettonWalletAddress, msg.amount, COMMISSION * 3, COMMISSION * 2);
    }

    receive(msg: SendLaunchTokensToPok){
        require(sender() == self.marketMaker, "Access is only for the market maker");
        require(self.launchJettonBalance > 0 && msg.amount <=self.launchJettonBalance, "Not enought launch tokens balance");
        require(self.pokCount > 0, "No POC contracts added");
        
        let totalFee = COMMISSION * 4 * self.pokCount;
        require(context().value >= totalFee + COMMISSION, "Insufficient funds to cover commission");
        let sendedAmount = 0;
        // Calculate and send launch tokens to each POC based on their share percentage
        foreach(pokAddress, sharePercentage in self.pokSharePercentages){
            if (self.pokActiveStatuses.exists(pokAddress) && self.pokActiveStatuses.get(pokAddress)!!) {
                let amountToSend: Int = (msg.amount * sharePercentage) / MAX_PERCENT;
                if (amountToSend > 0) {
                    sendedAmount += amountToSend;
                    transferTokensTo(self.launchJettonWalletAddress, pokAddress, amountToSend, COMMISSION * 4, COMMISSION * 3);
                }
            }
        }
        self.launchJettonBalance -= sendedAmount;
    }

    receive(){

    }

    receive(msg: JettonTransferNotification){
        if(sender() == self.launchJettonWalletAddress && msg.sender == myAddress()){
            // Update launch jetton balance
            self.launchJettonBalance = msg.amount;
        }
    }

    receive(msg: SetDao){
        require(sender() == self.owner, "Access is only for the owner");
        require(self.dao == self.owner, "DAO can only be set when current DAO equals owner");
        self.dao = msg.dao;
    }

    receive(msg: ChangeOwner){
        require(sender() == self.owner, "Access is only for the owner");
        require(msg.newOwner != newAddress(0, 0), "New owner address cannot be null");
        require(msg.newOwner != self.dao, "New owner address cannot be dao address");
        self.owner = msg.newOwner;
    }

    receive(msg: ChangeMarketMaker){
        require(sender() == self.dao, "Access is only for the dao");
        require(msg.newMarketMaker != newAddress(0, 0), "New market maker address cannot be null");
        self.marketMaker = msg.newMarketMaker;
    }

    receive(msg: SetRoyaltyWalletAddress){
        require(sender() == self.dao, "Access is only for the dao");
        require(msg.newRoyaltyWalletAddress != newAddress(0, 0), "New royalty wallet address cannot be null");
        self.newRoyaltyWalletAddress = msg.newRoyaltyWalletAddress;
    }

    receive(msg: UpdateRoyaltyWalletOnPoc){
        require(sender() == self.owner, "Access is only for the owner");
        require(self.newRoyaltyWalletAddress != newAddress(0, 0), "New royalty wallet address is not set");
        require(context().value >= COMMISSION, "Insufficient funds to cover commission");
        
        // Send ChangeRoyaltyWallet to the specified POC contract
        reserveAtMost(context().value);
        message(MessageParameters{
            to: msg.pokAddress,
            value: 0,
            mode: SendRemainingBalance | SendIgnoreErrors,
            body: ChangeRoyaltyWallet{newRoyaltyWalletAddress: self.newRoyaltyWalletAddress}.toCell()
        });
    }

    receive(msg: BlockDeferredWithdrawalOnPoc){
        require(sender() == self.owner, "Access is only for the owner");
        require(context().value >= COMMISSION, "Insufficient funds to cover commission");
        reserveAtMost(context().value);
        message(MessageParameters{
            to: msg.pokAddress,
            value: 0,
            mode: SendRemainingBalance | SendIgnoreErrors,
            body: msg.isForJetton ? StopJettonDeferredWithdrawal{}.toCell() : StopCollateralDeferredWithdrawal{}.toCell()
        });            
    }

    receive(msg: WithdrawEarning) {
        require(context().value >= COMMISSION * 2, "Not enought fee");
        require(sender() == self.owner, "Access is only for owner");
        reserveAtMost(context().value);
        message(MessageParameters{
            to: msg.pokAddress,
            value: 0,
            mode: SendRemainingBalance | SendIgnoreErrors,
            body: GetProfitOnRequest{}.toCell()
        });
    }

    receive(msg: WithdrawAdditionalJettons){
        require(sender() == self.marketMaker, "Access is only for the market maker");
        require(msg.amount > 0, "Amount must be greater than 0");
        require(msg.jettonWalletAddress != newAddress(0, 0), "Additional jetton wallet address is not set");
        require(msg.jettonWalletAddress != self.launchJettonWalletAddress, "Additional jetton wallet address is the launch jetton wallet");
        let isCollateral = false;
        foreach(master, wallet in self.collateralWalletAddresses){
            if(wallet==msg.jettonWalletAddress){
                isCollateral = true;
            }
        }
        require(!isCollateral, "Additional jetton wallet address is a collateral");
        transferTokensTo(msg.jettonWalletAddress, self.marketMaker, msg.amount, COMMISSION, 1);
    }
}

fun reserveAtMost(value: Int) {
    let toLeaveOnBalance = (myBalance() - value) + myStorageDue();
    nativeReserve(toLeaveOnBalance, ReserveAtMost);
}

fun transferTokensTo(toAddress: Address, recipient: Address, amount: Int, value: Int, forwardTonAmount: Int) {
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
            forwardPayload: emptySlice(),
        }.toCell(),
    });
}