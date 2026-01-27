import "@stdlib/deploy";
import "./messages";
const COMMISSION: Int = ton("0.05"); // 0.05 TON
const MAX_PERCENT: Int = 1000; // Maximum percentage value (1000 = 100%, 10 = 1%, 1 = 0.1%)

//1. добавляем пок с помощью сообщения AddPoc, оно отправляет FetchContractInfoAfterUpdatePoc на пок (DAO)
//2. получаем адрес жетонвалета для колатерала с добавленного пока с помощью сообщения GetContractInfoAfterUpdatePoc
//   отправляет ProvideWalletAddress на мастер колатерала и на мастер лаунча если он не был получен ранее, устанавливает настройки для пока (лок, колатерал)
//3. устанавливаем долю для пока с помощью сообщения SetPocSharePercentage
//4. отправляем колатерал на контракты поков с помощью сообщения TransferCollateralToPok
//5. отправляем лаунч токены на самого себя чтобы определить баланс лаунч токенов с помощью сообщения LaunchSelfSend (MM)
//6. отправляет лаунч токены на контракты поков с указанной пропорцией с помощью сообщения SendLaunchTokensToPok (MM)
//7. запрашиваем у пока данные по локу с помощью сообщения GetPocLockDate
// Выводим рандомные токены которые к нам прилетели с помощью сообщения WithdrawAdditionalJettons
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
    collateralMasterAddress: Address;
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

message(0x6) GetPocLockDate {
    queryId: Int as uint64;
    originalGasTo: Address;
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

message(0xa) SetReturnWalletAddress {
    newReturnWalletAddress: Address;
}

message(0xb) UpdateRoyaltyWalletOnPoc {
    pokAddress: Address;
}

message(0xc) BlockDeferredWithdrawalOnPoc {
    pokAddress: Address;
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
    pokLockDates: map<Address, Int as uint64>; // Map of pok addresses (k - pok address, v - lock date)
    pokCollateralAddresses: map<Address, Address>; // Map of pok addresses (k - pok address, v - collateral jetton master address)
    pokSharePercentages: map<Address, Int as uint16>; // Map of pok addresses (k - pok address, v - share percentage)
    pokCount: Int as uint8 = 0;

    newReturnWalletAddress: Address = newAddress(0, 0);
    isRoyaltyChangeEnabled: Bool = false;

    init(launchJettonMasterAddress: Address, marketMaker: Address){
        self.owner = sender();
        self.dao = sender();
        self.marketMaker = marketMaker;
        self.launchJettonMasterAddress = launchJettonMasterAddress;
    }


    receive(msg: AddPoc){
        require(sender() == self.dao, "Access is only for the dao");
        require(msg.pokAddress != newAddress(0, 0), "Pok address cannot be null");
        require(!self.pokActiveStatuses.exists(msg.pokAddress), "Pok already exists");
        self.pokActiveStatuses.set(msg.pokAddress, false);
        message(MessageParameters{
            to: msg.pokAddress,
            value: COMMISSION,
            mode: SendRemainingValue,
            body: FetchContractInfoAfterUpdatePoc{queryId: now(), originalGasTo: msg.originalGasTo}.toCell()
        });
    }

    receive(msg: GetContractInfoAfterUpdatePoc){
        require(self.pokActiveStatuses.exists(sender()), "Invalid sender");
        self.pokActiveStatuses.set(sender(), msg.isActive);
        self.pokCollateralAddresses.set(sender(), msg.jettonCollateralAddress);
        self.collateralAllowedAddresses.set(msg.jettonCollateralAddress, true);
        self.pokCount+=1;
        message(MessageParameters{
            to: msg.jettonCollateralAddress,
            value: COMMISSION,
            mode: SendRemainingValue,
            body: ProvideWalletAddress{query_id: now(), owner_address: myAddress(), include_address: false}.toCell()
        });
        if(self.launchJettonWalletAddress == newAddress(0, 0)){
            message(MessageParameters{
                to: msg.jettonLaunchAddress,
                value: COMMISSION,
                mode: SendRemainingValue,
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
        require(msg.sharePercentage > 0 && msg.sharePercentage <= MAX_PERCENT, "Share percentage must be between 1 and 1000");
        let usedPercents = 0;
        foreach(pok, percents in self.pokSharePercentages){
            usedPercents += percents;
        }
        require(usedPercents + msg.sharePercentage <= MAX_PERCENT, "Total share percentage cannot be greater than 100%");
        self.pokSharePercentages.set(msg.pokAddress, msg.sharePercentage);
    }


    receive(msg: TransferCollateralToPok){
        //если колатерал пустой, то отправляем тон
        require(msg.amount > 0, "Amount must be greater than 0");
        if(msg.collateralMasterAddress == newAddress(0, 0)){
            message(MessageParameters{
                to: msg.pokAddress,
                value: msg.amount,
                mode: SendRemainingValue,
                body: "Transfer collateral (TON) to pok".asComment()
            });
        }else{
            require(self.collateralWalletAddresses.exists(msg.collateralMasterAddress), "Collateral master address is not found");
            require(self.pokCollateralAddresses.exists(msg.pokAddress) && self.pokCollateralAddresses.get(msg.pokAddress)!! == msg.collateralMasterAddress, "Pok collateral address is not equal to collateral master address");
            transferTokensTo(self.collateralWalletAddresses.get(msg.collateralMasterAddress)!!, msg.pokAddress, msg.amount, "Transfer collateral to pok");
        }
    }

    receive(msg: LaunchSelfSend){
        require(sender() == self.marketMaker, "Access is only for the market maker");
        transferTokensTo(self.launchJettonWalletAddress, self.launchJettonWalletAddress, msg.amount, "Launch self send");
    }

    receive(msg: SendLaunchTokensToPok){
        require(sender() == self.marketMaker, "Access is only for the market maker");
        require(self.launchJettonBalance > 0, "No launch tokens balance");
        require(self.pokCount > 0, "No POC contracts added");
        
        let totalFee = COMMISSION * self.pokCount;
        require(context().value >= totalFee, "Insufficient funds to cover commission");
        let sendedAmount = 0;
        // Calculate and send launch tokens to each POC based on their share percentage
        foreach(pokAddress, sharePercentage in self.pokSharePercentages){
            if (self.pokActiveStatuses.exists(pokAddress) && self.pokActiveStatuses.get(pokAddress)!!) {
                let amountToSend: Int = (msg.amount * sharePercentage) / MAX_PERCENT;
                if (amountToSend > 0) {
                    sendedAmount += amountToSend;
                    transferTokensTo(self.launchJettonWalletAddress, pokAddress, amountToSend, "Send launch tokens to pok");
                }
            }
        }
        self.launchJettonBalance -= sendedAmount;
    }

    receive(){

    }

    receive(msg: JettonTransferNotification){
        if(sender() == self.launchJettonWalletAddress){
            //пришёл лаунч токены
            self.launchJettonBalance += msg.amount;
        } else {
            //пришёл коллатерал токены
        }
    }

    receive(msg: GetPocLockDate){
        require(sender() == self.marketMaker, "Access is only for the market maker");
        require(self.pokActiveStatuses.exists(msg.pokAddress), "Pok is not found");
        require(self.pokActiveStatuses.get(msg.pokAddress)!!, "Pok is not active");
        require(self.pokLockDates.exists(msg.pokAddress), "Pok lock date is not found");
        message(MessageParameters{
            to: msg.pokAddress,
            value: COMMISSION,
            mode: SendRemainingValue,
            body: FetchLockEndTime{queryId: now(), originalGasTo: msg.originalGasTo}.toCell()
        });
    }

    receive(msg: GetLockEndTime){
        require(self.pokActiveStatuses.exists(sender()), "Pok is not found");
        self.pokLockDates.set(sender(), msg.collateralJettonDeferredWTHDate);
    }

    receive(msg: SetDao){
        require(sender() == self.owner, "Access is only for the owner");
        require(self.dao == self.owner, "DAO can only be set when current DAO equals owner");
        self.dao = msg.dao;
    }

    receive(msg: ChangeOwner){
        require(sender() == self.dao, "Access is only for the dao");
        require(msg.newOwner != newAddress(0, 0), "New owner address cannot be null");
        require(msg.newOwner != self.dao, "New owner address cannot be null");
        self.owner = msg.newOwner;
    }

    receive(msg: ChangeMarketMaker){
        require(sender() == self.dao, "Access is only for the dao");
        require(msg.newMarketMaker != newAddress(0, 0), "New market maker address cannot be null");
        self.marketMaker = msg.newMarketMaker;
    }

    receive(msg: SetReturnWalletAddress){
        require(sender() == self.dao, "Access is only for the dao");
        require(msg.newReturnWalletAddress != newAddress(0, 0), "New return wallet address cannot be null");
        self.newReturnWalletAddress = msg.newReturnWalletAddress;
    }

    receive(msg: UpdateRoyaltyWalletOnPoc){
        require(sender() == self.owner, "Access is only for the owner");
        require(self.newReturnWalletAddress != newAddress(0, 0), "New return wallet address is not set");
        require(self.pokActiveStatuses.exists(msg.pokAddress), "POC is not found");
        require(self.pokActiveStatuses.get(msg.pokAddress)!!, "POC is not active");
        require(context().value >= COMMISSION, "Insufficient funds to cover commission");
        
        // Send ChangeRoyaltyWallet to the specified POC contract
        message(MessageParameters{
            to: msg.pokAddress,
            value: COMMISSION,
            mode: SendRemainingValue,
            body: ChangeRoyaltyWallet{newRoyaltyWalletAddress: self.newReturnWalletAddress}.toCell()
        });
    }

    receive(msg: BlockDeferredWithdrawalOnPoc){
        require(sender() == self.owner, "Access is only for the owner");
        require(self.pokActiveStatuses.exists(msg.pokAddress), "POC is not found");
        require(self.pokActiveStatuses.get(msg.pokAddress)!!, "POC is not active");
        require(context().value >= COMMISSION, "Insufficient funds to cover commission");
        
        // Send BlockDeferredWithdrawal to the specified POC contract to block/allow deferred withdrawal
        message(MessageParameters{
            to: msg.pokAddress,
            value: COMMISSION,
            mode: SendRemainingValue,
            body: BlockDeferredWithdrawal{}.toCell()
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
        transferTokensTo(msg.jettonWalletAddress, self.marketMaker, msg.amount, "Withdraw additional jettons");
    }

    fun _isActive(): Bool {
        if (self.pokCount == 0) {
            return false;
        }
        
        let maxLockDate: Int = 0;
        foreach(pokAddress, _ in self.pokActiveStatuses){
            if(self.pokLockDates.get(pokAddress) == null){
                return false;
            }
            let lockDate = self.pokLockDates.get(pokAddress)!!;
            if (lockDate > maxLockDate) {
                maxLockDate = lockDate;
            }
        }
        
        // Return true if the latest lock date is less than current time (all locks are expired)
        return maxLockDate < now();
    }

    get fun isActive(): Bool {
        return self._isActive();
    }
}

fun transferTokensTo(toAddress: Address, recipient: Address, amount: Int, comment: String) {
    let textComment: StringBuilder = beginString();
        textComment.append(comment);

    let forwardPayload: Cell = beginCell()
        .storeUint(0, 32)
        .storeRef(textComment.toCell())
        .endCell();

    message(MessageParameters{
            to: toAddress,
            value: COMMISSION,
            body: JettonTransfer{
                queryId: now(),
                amount: amount,
                destination: recipient,
                responseDestination: recipient,
                customPayload: null,
                forwardTonAmount: 1,
                forwardPayload: forwardPayload.asSlice()
            }.toCell(),
    });
}