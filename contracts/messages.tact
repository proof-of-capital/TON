message(0x2c76b973) ProvideWalletAddress {
    query_id: Int as uint64;
    owner_address: Address;
    include_address: Bool;
}

message(0xd1735400) TakeWalletAddress {
    query_id: Int as uint64;
    wallet_address: Address;
}

message ExtendLock {
    additionalTime: Int as uint32;
}

message(0x7362d09c) JettonTransferNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    forwardPayload: Slice as remaining;
}

message(0xf8a7ea5) JettonTransfer {
    queryId: Int as uint64;
    amount: Int as coins;
    destination: Address;
    responseDestination: Address?;
    customPayload: Cell? = null;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(0x595f07bc) JettonBurn {
    queryId: Int as uint64;
    amount: Int as coins;
    responseDestination: Address?;
    customPayload: Cell? = null;
}

message ChangeReturnWallet {
    newReturnWalletAddress: Address;
}

message WithdrawAllTons {}

message WithdrawAllCoins {}

message WithdrawAllSupportCoins {}

message AddAdditionalJettonData {
    newAdditionalJettonWalletAddress: Address;
    amount: Int as coins;
}

message WithdrawUnusedTons {}

message ChangeCommissionValue {
    commissionValue: Int as coins;
}

message AssignNewOwner {
    newOwner: Address;
}

message AssignNewReserveOwner {
    reserveOwner: Address;
}

message SwitchProfitMode {
    flag: Bool;
}

message GetProfitOnRequest {}

message ChangeRoyaltyWallet {
    newRoyaltyWalletAddress: Address;
}

message AddMarketMakerAddresses {
    newMarketMakerAddresse: Address;
}

message DeleteMarketMakerAddresses {
    delMarketMakerAddresse: Address;
}

message ChangeProfitPercentage {
    newRoyaltyProfitPercentage: Int as uint8;
}

message BlockDeferredWithdrawal { }

message JettonDeferredWithdrawal {
    amount: Int as coins;
    recipientAddress: Address;
}

message SupportDeferredWithdrawal {
    recipientAddress: Address;
}

message StopJettonDeferredWithdrawal { }
message StopSupportDeferredWithdrawal { }

message ConfirmJettonDeferredWithdrawal { }
message ConfirmSupportDeferredWithdrawal { }

message OldContractAddress {
    oldContractAddress: Address;
}

message GetLockEndTime {
    queryId: Int as uint64;
    originalGasTo: Address;
    lockEndTime: Int as uint32;
    mainJettonDeferredWTHDate: Int as uint32;
    supportJettonDeferredWTHDate: Int as uint32;
}

message GetCurrentPrice {
    queryId: Int as uint64;
    originalGasTo: Address;
    currentPrice: Int as coins;
}

message GetNumberOfMarketMakers {
    queryId: Int as uint64;
    originalGasTo: Address;
    currentNumber: Int as uint8;
}





message(0x163572b9) PurchaseIsSuccess {
} 


message FetchLockEndTime {
    queryId: Int as uint64;
    originalGasTo: Address;
}

message FetchCurrentPrice {
    queryId: Int as uint64;
    originalGasTo: Address;
}

message FetchNumberOfMarketMakers {
    queryId: Int as uint64;
    originalGasTo: Address;
}

message SetFarm {
    farm: Address;
}

message PaybackToFarm {}

message PriceGrowthBuyback {}

message FetchContractInfoAfterUpdatePoc {
    queryId: Int as uint64;
    originalGasTo: Address;
}

message GetContractInfoAfterUpdatePoc {
    queryId: Int as uint64;
    originalGasTo: Address;
    jettonSupportAddress: Address;
    jettonLaunchAddress: Address;
    isActive: Bool;
    currentPrice: Int as coins;
}

// New messages for jetton transfers with specific payloads
message MainJettonDeferredWithdrawal {}

message SupportJettonDeferredWithdrawal {}

message SendOtherJettonsToOwner {}

message SendChangeToOwner {}

message SendBackToOwner {}

message SendProfitToOwner {}

message SendProfitToRoyalty {}

message SupportBuyback {}

message TransferAllMainJettonsToOwner {}

message SendAllSupportBalanceToOwner {}