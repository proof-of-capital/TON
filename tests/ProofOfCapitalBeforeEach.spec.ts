import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { beginCell, toNano } from '@ton/core';
import { ProofOfCapital } from '../wrappers/ProofOfCapital';
import { checkPeriod, extractContractData } from './Utils'
import '@ton/test-utils';
// import fc from "fast-check";

// TODO: Test calculate-functions results before and after trend change
// TODO: Call `calculateJettonsToGiveForTonAmount`, `calculateTonToPayForTokenAmount`,
//       and `calculateTonForTokenAmountEarned` in different order to ensure there are
//       no anomalies in contract's state changes
// TODO: Run tests with different blockchain time value (`now()`)
// TODO: Write access control tests
// TODO: Ensure that `myBalance() >= self.contractTonBalance` after state changes
// TODO: Ensure that `self.contractJettonBalance <= self.contractJettonsSold` after state changes

// Initial jettons balance
const JETTONS_BALANCE = 10000000000n;

describe('ProofOfCapital', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let marketMaker: SandboxContract<TreasuryContract>;
    let jettonMaster: SandboxContract<TreasuryContract>;
    let returnWallet: SandboxContract<TreasuryContract>;
    let royaltyWallet: SandboxContract<TreasuryContract>;
    let proofOfCapital: SandboxContract<ProofOfCapital>;
    let otherAddress: SandboxContract<TreasuryContract>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        marketMaker = await blockchain.treasury('marketMaker');
        jettonMaster = await blockchain.treasury('jettonMaster');
        deployer = await blockchain.treasury('deployer');
        returnWallet = await blockchain.treasury('returnWallet');
        royaltyWallet = await blockchain.treasury('royaltyWallet');

        otherAddress = await blockchain.treasury('otherAddress');

        proofOfCapital = blockchain.openContract(
            await ProofOfCapital.fromInit(
            /*id=*/0n,
            /*owner=*/deployer.address,
            /*marketMakerAddress=*/marketMaker.address,
            /*jettonMasterAddress=*/jettonMaster.address,
            /*returnWalletAddress=*/returnWallet.address,
            /*royaltyWalletAddress=*/royaltyWallet.address,
            /*lockEndTime=*/BigInt(Math.floor(Date.now() / 1000) + 3600),
            /*initialPricePerToken=*/15000n,
            /*firstLevelJettonQuantity=*/5000000000000000n,
            /*priceIncrementMultiplier=*/50n,
            /*levelIncreaseMultiplier=*/20n,
            /*trendChangeStep=*/20n,
            /*levelIncreaseMultiplierafterTrend=*/9n,
            /*profitPercentage=*/100n/*10%*/,
            /*offsetJettons=*/15000000000000n,
            /*controlPeriod=*/21500n,
            /*jettonSupport*/false,
            /*jettonSupportMasterAddress*/jettonMaster.address,
            /*royaltyProfitPercentage*/1n
            ));
        const deployResult = await proofOfCapital.send(
            deployer.getSender(),
            { value: toNano('0.05'), },
            { $$type: 'Deploy', queryId: 0n, }
        );
        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: proofOfCapital.address,
            deploy: true,
            success: true,
        });
        await takeAddress();
        await topupJettons();
    });

    // describe('checkPeriod', () => {
    //     it('returns MinControlPeriod if period is less than MinControlPeriod', () => {
    //         expect(checkPeriod(10000)).toEqual(21600);
    //     });

    //     it('returns MinControlPeriod if period is equal MinControlPeriod', () => {
    //         expect(checkPeriod(21600)).toEqual(21600);
    //     });

    //     it('returns SixtyDaysConstant if period is equal SixtyDaysConstant', () => {
    //         expect(checkPeriod(5184000)).toEqual(5184000);
    //     });
    
    //     it('returns SixtyDaysConstant if period is greater than SixtyDaysConstant', () => {
    //         expect(checkPeriod(6000000)).toEqual(5184000);
    //     });
    
    //     it('returns the same period if it is within range', () => {
    //         expect(checkPeriod(3000000)).toEqual(3000000);
    //     });
    // });

    // it('get contract state', async () => {
    //     const result_1 = await proofOfCapital.getAddressesContractState();
    //     console.log('Contract addresses Output:', result_1);
    //     const result_2 = await proofOfCapital.getDatesContractState();
    //     console.log('Contract dates Output:', result_2);
    //     const result_3 = await proofOfCapital.getStandardContractStateJettonValues();
    //     console.log('Contract jetton values Output:', result_3);
    //     const result_4 = await proofOfCapital.getStandardContractStateTonValues();
    //     console.log('Contract ton values Output:', result_4);
    //     const result_5 = await proofOfCapital.getContractStateOffsetValues();
    //     console.log('Contract offset values Output:', result_5);
    //     const result_6 = await proofOfCapital.getContractConstantValues();
    //     console.log('Contract constant values Output:', result_6);
    // });

    async function takeAddress() {
        const result = await proofOfCapital.send(
            jettonMaster.getSender(),
            { value: toNano('0.5') },
            {
                $$type: 'TakeWalletAddress',
                query_id: 0n,
                wallet_address: jettonMaster.address,
            },
        );
        expect(result.transactions).toHaveTransaction({
            from: jettonMaster.address,
            to: proofOfCapital.address,
            op: 0xd1735400,
            success: true,
        });
    }

    // it('check offset values', async () => {
    //     const contractOffsetValues = extractContractData(await proofOfCapital.getContractStateOffsetValues())
    //     // console.log(contractOffsetValues);

    //     const result = await proofOfCapital.getCalculateOffset(15000000000000n)
    //     expect(result).toEqual(0n)
    //     const newcontractOffsetValues = extractContractData(await proofOfCapital.getContractStateOffsetValues())
    //     // console.log(newcontractOffsetValues)
    // });
    // 0
    // offset_step 0
    // remainder_offset_jettons 4970000000000000
    // size_offset_step 5000000000000000
    // offset_price 15000
    // current_step 0
    // quantity_jettons_per_level 5000000000000000
    // global_current_price 15000
    // global_remainder_of_step 4970000000000000
    // contract_jetton_balance 15000000000000
    // total_jettons_sold 15000000000000

    // it('should initialize with correct values', async () => {
    //     expect(await proofOfCapital.getJettonWalletAddress()).not.toEqual(deployer.address)
    //     expect(await proofOfCapital.getOffsetJettons()).toEqual(15000000000000n);
    //     expect(await proofOfCapital.getControlPeriod()).toEqual(21600n);
    // });

    async function topupJettons() {
        const jettonSendResult = await proofOfCapital.send(
            jettonMaster.getSender(),
            { value: toNano('0.5') },
            {
                $$type: 'JettonTransferNotification',
                queryId: 0n,
                amount: JETTONS_BALANCE,
                sender: deployer.address,
                forwardPayload: beginCell().endCell().asSlice(),
            },
        );
        expect(jettonSendResult.transactions).toHaveTransaction({
            from: jettonMaster.address,
            to: proofOfCapital.address,
            op: 0x7362d09c,
            success: true,
        });
    }

    it('should deploy', async () => {
        const now = Math.floor(Date.now() / 1000);
        const lockEndTime = Number(await proofOfCapital.getLockEndTime()) + now;


    });

    it('should allow owner to update contract balance', async () => {
        const result = await proofOfCapital.send(
            deployer.getSender(),
            { value: toNano('1') }, 
            null);
    
        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: proofOfCapital.address,
            success: true,
        });
    });
    
    // it('should allow if sender is not market maker during lock period', async () => {
    //     const result = await proofOfCapital.send(
    //         jettonMaster.getSender(), 
    //         { value: toNano('1') }, 
    //         null
    //     );
    
    //     expect(result.transactions).toHaveTransaction({
    //         from: jettonMaster.address,
    //         to: proofOfCapital.address,
    //         success: true,
    //     });
    // });
    
    // it('should allow market maker to trade during lock period', async () => {
    //     const result = await proofOfCapital.send(
    //         marketMaker.getSender(),
    //         { value: toNano('1') },
    //         null
    //     );
    
    //     expect(result.transactions).toHaveTransaction({
    //         from: marketMaker.address,
    //         to: proofOfCapital.address,
    //         success: true,
    //     });
    // });

    // async function topupJettonsnotfromownerwithoutBuyback() {
    //     const jettonSendResult = await proofOfCapital.send(
    //         jettonMaster.getSender(),
    //         { value: toNano('2') },
    //         {
    //             $$type: 'JettonTransferNotification',
    //             queryId: 0n,
    //             amount: 1000000000000000n,
    //             sender: otherAddress.address,
    //             forwardPayload: beginCell().endCell().asSlice(),
    //         },
    //     );
    //     expect(jettonSendResult.transactions).toHaveTransaction({
    //         from: jettonMaster.address,
    //         to: proofOfCapital.address,
    //         op: 0x7362d09c,
    //         success: false,
    //         exitCode: 17187,
    //     });
    // }

    // it('check popUp jettons not from owner without buyback balance', async () => {
    //     await topupJettonsnotfromownerwithoutBuyback();
    // })

    async function topupJettonsnotfromownerwithincorrectcommission() {
        const jettonSendResult = await proofOfCapital.send(
            jettonMaster.getSender(),
            { value: toNano('0.04') },
            {
                $$type: 'JettonTransferNotification',
                queryId: 0n,
                amount: 1000000000000000n,
                sender: otherAddress.address,
                forwardPayload: beginCell().endCell().asSlice(),
            },
        );
        expect(jettonSendResult.transactions).toHaveTransaction({
            from: jettonMaster.address,
            to: proofOfCapital.address,
            op: 0x7362d09c,
            success: false,
            exitCode: 35895,
        });
    }

    it('check popUp jettons not from owner incorrect commission', async () => {
        await topupJettonsnotfromownerwithincorrectcommission();
    });

    
    it('should fail if value is less than commission', async () => {
        const result = await proofOfCapital.send(
            otherAddress.getSender(),
            { value: toNano('0.01') }, // Less than commission
            null
        );

        expect(result.transactions).toHaveTransaction({
            success: false,
            exitCode: 17552
        })
    });

    // describe('check receive ExtendLock', () => {
    //     it('should succeed for 10 minutes', async () => {
    //         const sendadditionalTime = 600n; 
    //         const oldextractedData = extractContractData(await proofOfCapital.getDatesContractState())['Lock end time']
    //         console.log(oldextractedData)
    //         const inititalLockEndDate = BigInt(oldextractedData);
    //         const ExtendLockSendResult = await proofOfCapital.send(
    //             deployer.getSender(),
    //             { value: toNano('0.01') },
    //             {
    //                 $$type: 'ExtendLock',
    //                 additionalTime: sendadditionalTime
    //             }
    //         );
    
    //         expect(ExtendLockSendResult.transactions).toHaveTransaction({
    //             from: proofOfCapital.address,
    //             to: deployer.address,
    //             success: true,
    //         });

    //         await new Promise(resolve => setTimeout(resolve, 4000));
    
    //         const newextractedData = extractContractData(await proofOfCapital.getDatesContractState());
    //         console.log(newextractedData);
    //         const newLockEndDate = BigInt(newextractedData['Lock end time']);
    
    //         expect(newLockEndDate).toEqual(inititalLockEndDate);
    //     });
    
        // it('should succeed for half a year', async () => {
        //     const sendadditionalTime = 15768000n; 
        //     const initialRemainingSeconds = await proofOfCapital.getRemainingSeconds();
    
        //     const ExtendLockSendResult = await proofOfCapital.send(
        //         deployer.getSender(),
        //         { value: toNano('0.01') },
        //         {
        //             $$type: 'ExtendLock',
        //             additionalTime: sendadditionalTime
        //         }
        //     );
    
        //     expect(ExtendLockSendResult.transactions).toHaveTransaction({
        //         from: proofOfCapital.address,
        //         to: deployer.address,
        //         success: true,
        //     });
    
        //     const newRemainingSeconds = await proofOfCapital.getRemainingSeconds();
    
        //     expect(newRemainingSeconds).toEqual(initialRemainingSeconds + sendadditionalTime);
        // });
    
        // it('should fail if sender is not the owner', async () => {
        //     const sendadditionalTime = 600n; 
        //     const ExtendLockSendResult = await proofOfCapital.send(
        //         otherAddress.getSender(), 
        //         { value: toNano('0.01') },
        //         {
        //             $$type: 'ExtendLock',
        //             additionalTime: sendadditionalTime
        //         }
        //     );
    
        //     expect(ExtendLockSendResult.transactions).toHaveTransaction({
        //         from: otherAddress.address,
        //         to: proofOfCapital.address,
        //         success: false,
        //         exitCode: 401, 
        //     });
        // });
    
        // it('should fail if commission is less than required', async () => {
        //     const sendadditionalTime = 600n; 
        //     const ExtendLockSendResult = await proofOfCapital.send(
        //         deployer.getSender(),
        //         { value: toNano('0.005') }, 
        //         {
        //             $$type: 'ExtendLock',
        //             additionalTime: sendadditionalTime,
        //         }
        //     );
    
        //     expect(ExtendLockSendResult.transactions).toHaveTransaction({
        //         from: deployer.address,
        //         to: proofOfCapital.address,
        //         success: false,
        //         exitCode: 35895, 
        //     });
        // });
    
        // it('should fail if additional time exceeds 2 years', async () => {
        //     const sendadditionalTime = 63072001n; 
        //     const ExtendLockSendResult = await proofOfCapital.send(
        //         deployer.getSender(),
        //         { value: toNano('0.01') },
        //         {
        //             $$type: 'ExtendLock',
        //             additionalTime: sendadditionalTime
        //         }
        //     );
    
        //     expect(ExtendLockSendResult.transactions).toHaveTransaction({
        //         from: deployer.address,
        //         to: proofOfCapital.address,
        //         success: false,
        //         exitCode: 12345, 
        //     });
        // });
    // });

    // // Tests the conversion of TON to jetton amounts, ensuring bounds and edge cases.
    // it("get ton_to_jetton_calculation", async () => {
    //     expect(await proofOfCapital.getTonToJettonCalculation(0n)).toEqual(0n)
    //     expect(await proofOfCapital.getTonToJettonCalculation(1n)).toEqual(66666n)
    //     expect(await proofOfCapital.getTonToJettonCalculation(2n)).toEqual(133333n)
    //     expect(await proofOfCapital.getTonToJettonCalculation(3n)).toEqual(200000n)
    //     expect(await proofOfCapital.getTonToJettonCalculation(1000n)).toEqual(66666666n)

    //     // TODO: This input should be rejected (C1 vuln)
    //     expect(await proofOfCapital.getTonToJettonCalculation(10000000n)).toEqual(JETTONS_BALANCE)

    //     expect(await proofOfCapital.getTonToJettonCalculation(-1n)).toEqual(0n)
    //     expect(await proofOfCapital.getTonToJettonCalculation(-1000000n)).toEqual(0n)
    // });

    // it('check match pattern addresses contract', async () => {
    //     const string_received = await proofOfCapital.getAddressesContractState();
    //     const reg_expression = /^! Addresses contract state !  \| Contract address: [A-Za-z0-9_=-]+ \| Owner: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G \| Jettom master address: EQACdYJF5I1R2lA1fU0_-mbkt6eav9vFkY4b6fv8S7Ku3vRT \| Market maker address: EQCmVXPpVSmOQGonhBgzag05NdEfVOeFSyc6DipzpyZfkJqU \| Return wallet address: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G \| Royalty wallet address: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G \| Contract jetton wallet address: EQACdYJF5I1R2lA1fU0_-mbkt6eav9vFkY4b6fv8S7Ku3vRT \| Additional jetton master address: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G \| Additional jetton wallet address: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G$/;
    //     // expect(string_received).toMatch(reg_expression);
    //     // пример получаемой строки - '! Addresses contract state !  | Owner: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G | Jettom master address: EQACdYJF5I1R2lA1fU0_-mbkt6eav9vFkY4b6fv8S7Ku3vRT | Market maker address: EQCmVXPpVSmOQGonhBgzag05NdEfVOeFSyc6DipzpyZfkJqU | Return wallet address: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G | Royalty wallet address: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G | Contract jetton wallet address: EQACdYJF5I1R2lA1fU0_-mbkt6eav9vFkY4b6fv8S7Ku3vRT | Additional jetton master address: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G | Additional jetton wallet address: EQBGhqLAZseEqRXz4ByFPTGV7SVMlI4hrbs-Sps_Xzx01x8G'
    // });

    // it('check match pattern contract dates', async () => {
    //     const string_received = await proofOfCapital.getDatesContractState();
    //     const reg_expression = /^! Dates contract state !  \| Lock end time: \d+ \| Control day: \d+ \| Control period: \d+$/;
    //     expect(string_received).toMatch(reg_expression);
    //     // expect(await proofOfCapital.getDatesContractState()).toEqual('! Dates contract state ! | Lock end time: 1737709870 | Control day: 1742893871 | Control period: 43200')
    // });

    // it('check equal contract jetton values', async () => {
    //     expect(await proofOfCapital.getStandardContractStateJettonValues()).toEqual('! Standart contract state jetton values !  | Initial price per token: 15000 | First level jetton quantity: 5000000000000000 | Total jettons sold: 15000000000000 | Contract jetton balance: 15010000000000 | Jettons earned: 0 | Quantity jettons per level: 5000000000000000 | Current step: 0 | Quantity jettons per level earned: 5000000000000000')
    // });

    // it('check equal contract ton values', async () => {
    //     expect(await proofOfCapital.getStandardContractStateTonValues()).toEqual('! Standart contract state ton values !  | Price increment multiplier: 50 | Commission: 50000000 | Level increase multiplier: 20 | Trend change step: 20 | Level decrease multiplier after trend: 9 | Profit percentage: 100 | Query id: 0 | Contract ton balance (by the contract itself): 0 | Contract real ton balance: 3.9419188 | Actual profit: 0 | Current price: 29690 | Remainder of step: 6467084581032389 | Current step earned: 0 | Remainder of step earned: 5000000000000000 | Current price earned: 15000')
    // });

    // it('check equal contract offset values', async () => {
    //     expect(await proofOfCapital.getContractStateOffsetValues()).toEqual('! Standart contract state ton values !  | Offset jettons: 80000000000000000 | Offset step: 14 | Offset price: 29690 | Remainder offset jettons: 6467084581032389 | Size offset step: 6597393815314358 | Call jettons ID: 2')
    // });

    // it('check equal contract constant values', async() => {
    //     expect(await proofOfCapital.getContractConstantValues()).toEqual('! Constants !  | Two years constant: 63072000 | Half year constant: 15768000 | Ten minutes constant: 600 | Commission constant: 50000000 | Sixty days constant: 5184000 | Min control period: 21600 | CommissionMultiplierConstant: 10')
    // });


});
