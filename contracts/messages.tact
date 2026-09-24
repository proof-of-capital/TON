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
    lockTimestamp: Int as uint64;
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

message WithdrawAllCollateralCoins {}

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

message BlockMigration { }

message JettonMigration {
    amount: Int as coins;
    recipientAddress: Address;
}

message CollateralMigration {
    recipientAddress: Address;
}

message StopJettonMigration { }
message StopCollateralMigration { }

message ConfirmJettonMigration { }
message ConfirmCollateralMigration { }

message GetCurrentPrice {
    queryId: Int as uint64;
    originalGasTo: Address;
    currentPrice: Int as coins;
}

message(0x163572b9) PurchaseIsSuccess {
} 

message FetchCurrentPrice {
    queryId: Int as uint64;
    originalGasTo: Address;
}

message SetDao {
    dao: Address;
}

message PaybackToDao {}

message PriceGrowthBuyback {}

message FetchContractInfoAfterUpdatePoc {
    queryId: Int as uint64;
    originalGasTo: Address;
}

message GetContractInfoAfterUpdatePoc {
    queryId: Int as uint64;
    originalGasTo: Address;
    jettonCollateralAddress: Address;
    jettonLaunchAddress: Address;
    isActive: Bool;
    currentPrice: Int as coins;
    lockDate: Int as uint64;
}

// New messages for jetton transfers with specific payloads
message LaunchJettonMigration {}

message CollateralJettonMigration {}

message SendOtherJettonsToDao {}

message SendCollateralJettonsToDao {}

message SendChangeToOwner {}

message SendChangeToDao {}

message SendUnusedTonsToDao {}

message SendBackToOwner {}

message SendProfitToTheOwner {}

message SendProfitToRoyalty {}

message CollateralBuyback {}

message TransferAllLaunchJettonsToOwner {}

message SendAllCollateralBalanceToOwner {}
