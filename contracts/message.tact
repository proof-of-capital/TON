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

message Withdraw {
    amount: Int as coins;
}


message ChangeMarketMaker {
    newMarketMakerAddress: Address;
}

message ChangeReturnWallet {
    newReturnWalletAddress: Address;
}

message WithdrawAllTons {}

message WithdrawAllCoins {}

message AddAdditionalJettonData {
    newAdditionalJettonMasterAddress: Address;
    newAdditionalJettonWalletAddress: Address;
    amount: Int as coins;
}

message WithdrawUnusedTons {}
