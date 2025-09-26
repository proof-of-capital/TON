import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Address, beginCell, Cell, Slice, toNano } from '@ton/core';
import {
    ProofOfCapital,
    JettonTransferNotification,
    AddMarketMakerAddresses,
    TakeWalletAddress,
    CollateralDeferredWithdrawal,
    ConfirmCollateralDeferredWithdrawal,
    JettonDeferredWithdrawal,
    ConfirmJettonDeferredWithdrawal,
} from '../build/ProofOfCapital/tact_ProofOfCapital';
import { MyJetton, Mint } from '../build/MyJetton/tact_MyJetton';
import { JettonDefaultWallet, TokenTransfer, loadTokenTransfer } from '../build/MyJetton/tact_JettonDefaultWallet';
import '@ton/test-utils';
import { verifyTransactions } from './utils';

function expectBigIntClose(received: bigint, expected: bigint, tolerance: bigint = 100n) {
    const diff = received > expected ? received - expected : expected - received;
    expect(diff <= tolerance).toBe(true);
}

describe('ProofOfCapital', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let owner: SandboxContract<TreasuryContract>;
    let marketMaker: SandboxContract<TreasuryContract>;
    let proofOfCapital: SandboxContract<ProofOfCapital>;
    let supportJetton: SandboxContract<MyJetton>;
    let launchJetton: SandboxContract<MyJetton>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        deployer = await blockchain.treasury('deployer');
        owner = await blockchain.treasury('owner');
        marketMaker = await blockchain.treasury('marketMaker');

        supportJetton = blockchain.openContract(
            await MyJetton.fromInit(
                deployer.address,
                beginCell().storeUint(0, 8).storeStringTail('Support Token').endCell(),
                toNano('100000000000000000'),
            ),
        );

        await supportJetton.send(deployer.getSender(), { value: toNano('0.1') }, 'Mint: 100');

        launchJetton = blockchain.openContract(
            await MyJetton.fromInit(
                deployer.address,
                beginCell().storeUint(0, 8).storeStringTail('Launch Token').endCell(),
                toNano('100000000000000000000'),
            ),
        );

        await launchJetton.send(deployer.getSender(), { value: toNano('0.1') }, 'Mint: 100');

        const lockEndTime = BigInt(Math.floor(Date.now() / 1000) + 86400);
        const initialPricePerToken = toNano('0.001');
        const firstLevelJettonQuantity = toNano('10');
        const priceIncrementMultiplier = 50n;
        const levelIncreaseMultiplier = 20n;
        const trendChangeStep = 20n;
        const levelDecreaseMultiplierafterTrend = 9n;
        const profitPercentage = 100n;
        const offsetJettons = 0n;
        const controlPeriod = 60n;
        const jettonSupport = true;
        const royaltyProfitPercent = 200n;
        const coefficientProfit = 1000n;
        const jettonDecimals = 9n;

        proofOfCapital = blockchain.openContract(
            await ProofOfCapital.fromInit(
                1n,
                owner.address,
                marketMaker.address,
                launchJetton.address,
                owner.address,
                owner.address,
                lockEndTime,
                initialPricePerToken,
                firstLevelJettonQuantity,
                priceIncrementMultiplier,
                levelIncreaseMultiplier,
                trendChangeStep,
                levelDecreaseMultiplierafterTrend,
                profitPercentage,
                offsetJettons,
                controlPeriod,
                jettonSupport,
                supportJetton.address,
                royaltyProfitPercent,
                coefficientProfit,
                jettonDecimals,
            ),
        );

        const deployResult = await proofOfCapital.send(
            deployer.getSender(),
            {
                value: toNano('1.0'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            },
        );
        blockchain.now = deployResult.transactions[0].now + 100;
        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: proofOfCapital.address,
            deploy: true,
            success: true,
        });

        await verifyTransactions(deployResult.transactions, deployer.address);

        const transferSupportResultToOwner = await supportJetton.send(
            deployer.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'Mint',
                amount: toNano('100000'),
                receiver: owner.address,
            },
        );

        await verifyTransactions(transferSupportResultToOwner.transactions, deployer.address);

        const transferTokenResult = await launchJetton.send(
            deployer.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'Mint',
                amount: toNano('100000000000'),
                receiver: owner.address,
            },
        );

        await verifyTransactions(transferTokenResult.transactions, deployer.address);

        const transferToMarketMakerResult = await supportJetton.send(
            deployer.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'Mint',
                amount: toNano('100000000000'),
                receiver: marketMaker.address,
            },
        );

        await verifyTransactions(transferToMarketMakerResult.transactions, deployer.address);
        const ownerLaunchJettonWallet = blockchain.openContract(
            await JettonDefaultWallet.fromInit(owner.address, launchJetton.address),
        );

        const sendLaunchFromOwnerToPoc = await ownerLaunchJettonWallet.send(
            owner.getSender(),
            { value: toNano('0.5') },
            {
                $$type: 'TokenTransfer',
                query_id: 0n,
                amount: toNano('10000000'),
                recipient: proofOfCapital.address,
                response_destination: owner.address,
                custom_payload: null,
                forward_ton_amount: toNano('0.4'),
                forward_payload: beginCell().endCell().asSlice(),
            },
        );

        await verifyTransactions(sendLaunchFromOwnerToPoc.transactions, owner.address);
    });

    it('should migrate state from PoC A to PoC B preserving steps and offsets', async () => {
        const ownerLaunchJettonWallet = blockchain.openContract(
            await JettonDefaultWallet.fromInit(marketMaker.address, supportJetton.address),
        );
        for (let i = 0; i < 115; i++) {
            const sendLaunchFromMarketMakerToPoc = await ownerLaunchJettonWallet.send(
                marketMaker.getSender(),
                { value: toNano('14.6') },
                {
                    $$type: 'TokenTransfer',
                    query_id: 0n,
                    amount: toNano('10000000'),
                    recipient: proofOfCapital.address,
                    response_destination: marketMaker.address,
                    custom_payload: null,
                    forward_ton_amount: toNano('13.4'),
                    forward_payload: beginCell().endCell().asSlice(),
                },
            );

            await verifyTransactions(sendLaunchFromMarketMakerToPoc.transactions, marketMaker.address);
        }

        const currentStep = await proofOfCapital.getCurrentStep();
        const currentPrice = await proofOfCapital.getCurrentPrice();
        const offsetJettons = await proofOfCapital.getJettonSold();

        console.log(
            'Old contract state - Step:',
            currentStep.toString(),
            'Price:',
            currentPrice.toString(),
            'OffsetJettons:',
            offsetJettons.toString(),
        );

        const NEW_POC_ID = 2n;
        const NEW_POC_INITIAL_PRICE_PER_TOKEN = toNano('0.001');
        const NEW_POC_FIRST_LEVEL_JETTON_QUANTITY = toNano('10');
        const NEW_POC_PRICE_INCREMENT_MULTIPLIER = 50n;
        const NEW_POC_LEVEL_INCREASE_MULTIPLIER = 20n;
        const NEW_POC_TREND_CHANGE_STEP = 20n;
        const NEW_POC_LEVEL_DECREASE_MULTIPLIER_AFTER_TREND = 9n;
        const NEW_POC_PROFIT_PERCENTAGE = 100n;
        const NEW_POC_CONTROL_PERIOD = 21600n;
        const NEW_POC_JETTON_SUPPORT = true;
        const NEW_POC_ROYALTY_PROFIT_PERCENT = 200n;
        const NEW_POC_COEFFICIENT_PROFIT = 1000n;
        const NEW_POC_JETTON_DECIMALS = 9n;

        const newLockEndTime = BigInt(blockchain.now! + 365 * 24 * 3600);
        const newPocContract = blockchain.openContract(
            await ProofOfCapital.fromInit(
                NEW_POC_ID,
                owner.address,
                marketMaker.address,
                launchJetton.address,
                owner.address,
                owner.address,
                newLockEndTime,
                NEW_POC_INITIAL_PRICE_PER_TOKEN,
                NEW_POC_FIRST_LEVEL_JETTON_QUANTITY,
                NEW_POC_PRICE_INCREMENT_MULTIPLIER,
                NEW_POC_LEVEL_INCREASE_MULTIPLIER,
                NEW_POC_TREND_CHANGE_STEP,
                NEW_POC_LEVEL_DECREASE_MULTIPLIER_AFTER_TREND,
                NEW_POC_PROFIT_PERCENTAGE,
                offsetJettons,
                NEW_POC_CONTROL_PERIOD,
                NEW_POC_JETTON_SUPPORT,
                supportJetton.address,
                NEW_POC_ROYALTY_PROFIT_PERCENT,
                NEW_POC_COEFFICIENT_PROFIT,
                NEW_POC_JETTON_DECIMALS,
            ),
        );

        const deployNewPocResult = await newPocContract.send(
            deployer.getSender(),
            {
                value: toNano('1.0'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            },
        );

        expect(deployNewPocResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: newPocContract.address,
            deploy: true,
            success: true,
        });

        await verifyTransactions(deployNewPocResult.transactions, deployer.address);

        const deployedOwner = await newPocContract.getOwnerAddress();
        const deployedLaunchJettonMaster = await newPocContract.getJettonMasterAddress();
        const deployedReturnWallet = await newPocContract.getReturnWalletAddress();
        const deployedLockEndTime = await newPocContract.getLockEndTime();
        const deployedOffsetJettons = await newPocContract.getOffsetJettons();
        const deployedControlPeriod = await newPocContract.getControlPeriod();
        const deployedJettonSupport = await newPocContract.getIsJettonCollateral();
        const deployedJettonCollateralMaster = await newPocContract.getJettonCollateralMasterAddress();
        const deployedRoyaltyProfitPercent = await newPocContract.getRoyaltyProfitPercent();

        expect(deployedOwner.toString()).toBe(owner.address.toString());
        expect(deployedLaunchJettonMaster.toString()).toBe(launchJetton.address.toString());
        expect(deployedReturnWallet.toString()).toBe(owner.address.toString());
        expect(deployedLockEndTime).toBe(newLockEndTime);
        expect(deployedOffsetJettons).toBe(offsetJettons);
        expect(deployedControlPeriod).toBe(NEW_POC_CONTROL_PERIOD);
        expect(deployedJettonSupport).toBe(NEW_POC_JETTON_SUPPORT);
        expect(deployedJettonCollateralMaster.toString()).toBe(supportJetton.address.toString());
        expect(deployedRoyaltyProfitPercent).toBe(NEW_POC_ROYALTY_PROFIT_PERCENT);

        const setOldContractResult = await newPocContract.send(
            owner.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'OldContractAddress',
                oldContractAddress: proofOfCapital.address,
            },
        );

        expect(setOldContractResult.transactions).toHaveTransaction({
            from: owner.address,
            to: newPocContract.address,
            success: true,
        });

        await verifyTransactions(setOldContractResult.transactions, owner.address);

        const currentTime = Math.floor(Date.now() / 1000);
        const lockEndTime = await proofOfCapital.getLockEndTime();
        const timeToAdvance = Number(lockEndTime) - currentTime - 60 * 24 * 3600 + 3600;

        if (timeToAdvance > 0) {
            blockchain.now = currentTime + timeToAdvance;
        } else {
            blockchain.now = currentTime + 60 * 24 * 3600 + 3600;
        }

        const collateralDeferredWithdrawalResult = await proofOfCapital.send(
            owner.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'CollateralDeferredWithdrawal',
                recipientAddress: newPocContract.address,
            },
        );

        const launchDeferredWithdrawalResult = await proofOfCapital.send(
            owner.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'JettonDeferredWithdrawal',
                recipientAddress: newPocContract.address,
                amount: toNano('100000'),
            },
        );

        expect(collateralDeferredWithdrawalResult.transactions).toHaveTransaction({
            from: owner.address,
            to: proofOfCapital.address,
            success: true,
        });

        expect(launchDeferredWithdrawalResult.transactions).toHaveTransaction({
            from: owner.address,
            to: proofOfCapital.address,
            success: true,
        });

        const THIRTY_DAYS = 2_592_000;
        blockchain.now = blockchain.now + THIRTY_DAYS + 3600;

        const confirmLaunchWithdrawalResult = await proofOfCapital.send(
            owner.getSender(),
            { value: toNano('1.5') },
            {
                $$type: 'ConfirmJettonDeferredWithdrawal',
            },
        );
        const confirmCollateralWithdrawalResult = await proofOfCapital.send(
            owner.getSender(),
            { value: toNano('1.5') },
            {
                $$type: 'ConfirmCollateralDeferredWithdrawal',
            },
        );

        expect(confirmCollateralWithdrawalResult.transactions).toHaveTransaction({
            from: owner.address,
            to: proofOfCapital.address,
            success: true,
        });

        expect(confirmLaunchWithdrawalResult.transactions).toHaveTransaction({
            from: owner.address,
            to: proofOfCapital.address,
            success: true,
        });

        await verifyTransactions(confirmLaunchWithdrawalResult.transactions, owner.address, proofOfCapital.address);
        await verifyTransactions(confirmCollateralWithdrawalResult.transactions, owner.address);

        const newPocContractCollateralBalance = await newPocContract.getCollateralTokenBalance();
        const newPocContractJettonBalance = await newPocContract.getJettonBalance();

        expect(newPocContractCollateralBalance).toBeGreaterThan(0n);
        expect(newPocContractJettonBalance).toBeGreaterThan(0n);

        const oldContractAddress = await newPocContract.getOldContractAddress();
        expect(oldContractAddress.toString()).toBe(proofOfCapital.address.toString());

        const oldOffsetStep = await proofOfCapital.getOffsetStep();
        const oldRemainderOffsetJettons = await proofOfCapital.getRemainderOffsetJettons();
        const oldOffsetPrice = await proofOfCapital.getOffsetPrice();
        const oldSizeOffsetStep = await proofOfCapital.getSizeOffsetStep();

        const newOffsetStep = await newPocContract.getOffsetStep();
        const newRemainderOffsetJettons = await newPocContract.getRemainderOffsetJettons();
        const newOffsetPrice = await newPocContract.getOffsetPrice();
        const newSizeOffsetStep = await newPocContract.getSizeOffsetStep();

        expect(newOffsetStep).toBe(oldOffsetStep);
        expectBigIntClose(newSizeOffsetStep, oldSizeOffsetStep, 100n);
        expectBigIntClose(newOffsetPrice, oldOffsetPrice, 100n);
        expectBigIntClose(newRemainderOffsetJettons, oldRemainderOffsetJettons, 100n);

        console.log('Offset values verification:');
        console.log(
            'Old - Step:',
            oldOffsetStep.toString(),
            'Remainder:',
            oldRemainderOffsetJettons.toString(),
            'Price:',
            oldOffsetPrice.toString(),
            'Size:',
            oldSizeOffsetStep.toString(),
        );
        console.log(
            'New - Step:',
            newOffsetStep.toString(),
            'Remainder:',
            newRemainderOffsetJettons.toString(),
            'Price:',
            newOffsetPrice.toString(),
            'Size:',
            newSizeOffsetStep.toString(),
        );
    });

    it('should not migrate state from PoC A to PoC B preserving steps and offsets', async () => {
        const balance = await proofOfCapital.getJettonBalance();
        const balance2 = await proofOfCapital.getCollateralTokenBalance();

        console.log(balance, balance2);
        const ownerLaunchJettonWallet = blockchain.openContract(
            await JettonDefaultWallet.fromInit(marketMaker.address, supportJetton.address),
        );
        for (let i = 0; i < 115; i++) {
            const sendLaunchFromMarketMakerToPoc = await ownerLaunchJettonWallet.send(
                marketMaker.getSender(),
                { value: toNano('14.6') },
                {
                    $$type: 'TokenTransfer',
                    query_id: 0n,
                    amount: toNano('10000000'),
                    recipient: proofOfCapital.address,
                    response_destination: marketMaker.address,
                    custom_payload: null,
                    forward_ton_amount: toNano('13.4'),
                    forward_payload: beginCell().endCell().asSlice(),
                },
            );

            await verifyTransactions(sendLaunchFromMarketMakerToPoc.transactions, marketMaker.address);
        }
        const sendLaunchFromMarketMakerToPoc = await ownerLaunchJettonWallet.send(
            marketMaker.getSender(),
            { value: toNano('14.6') },
            {
                $$type: 'TokenTransfer',
                query_id: 0n,
                amount: toNano('9000000'),
                recipient: proofOfCapital.address,
                response_destination: marketMaker.address,
                custom_payload: null,
                forward_ton_amount: toNano('13.4'),
                forward_payload: beginCell().endCell().asSlice(),
            },
        );

        await verifyTransactions(sendLaunchFromMarketMakerToPoc.transactions, marketMaker.address);
        const balanceAfter = await proofOfCapital.getJettonBalance();
        const balance2After = await proofOfCapital.getCollateralTokenBalance();
        const pocLaunchJettonWallet = blockchain.openContract(
            await JettonDefaultWallet.fromInit(proofOfCapital.address, launchJetton.address),
        );

        const dataAfter = await pocLaunchJettonWallet.getGetWalletData();

        console.log('Balance after transfer:', balanceAfter.toString(), balance2After.toString());

        const currentStep = await proofOfCapital.getCurrentStep();
        const currentPrice = await proofOfCapital.getCurrentPrice();
        const offsetJettons = await proofOfCapital.getJettonSold();

        console.log(
            'Old contract state - Step:',
            currentStep.toString(),
            'Price:',
            currentPrice.toString(),
            'OffsetJettons:',
            offsetJettons.toString(),
        );

        const NEW_POC_ID = 2n;
        const NEW_POC_INITIAL_PRICE_PER_TOKEN = toNano('0.001');
        const NEW_POC_FIRST_LEVEL_JETTON_QUANTITY = toNano('10');
        const NEW_POC_PRICE_INCREMENT_MULTIPLIER = 50n;
        const NEW_POC_LEVEL_INCREASE_MULTIPLIER = 20n;
        const NEW_POC_TREND_CHANGE_STEP = 20n;
        const NEW_POC_LEVEL_DECREASE_MULTIPLIER_AFTER_TREND = 9n;
        const NEW_POC_PROFIT_PERCENTAGE = 100n;
        const NEW_POC_CONTROL_PERIOD = 21600n;
        const NEW_POC_JETTON_SUPPORT = true;
        const NEW_POC_ROYALTY_PROFIT_PERCENT = 200n;
        const NEW_POC_COEFFICIENT_PROFIT = 1000n;
        const NEW_POC_JETTON_DECIMALS = 9n;

        const newLockEndTime = BigInt(blockchain.now! + 365 * 24 * 3600);
        const newPocContract = blockchain.openContract(
            await ProofOfCapital.fromInit(
                NEW_POC_ID,
                owner.address,
                marketMaker.address,
                launchJetton.address,
                owner.address,
                owner.address,
                newLockEndTime,
                NEW_POC_INITIAL_PRICE_PER_TOKEN,
                NEW_POC_FIRST_LEVEL_JETTON_QUANTITY,
                NEW_POC_PRICE_INCREMENT_MULTIPLIER,
                NEW_POC_LEVEL_INCREASE_MULTIPLIER,
                NEW_POC_TREND_CHANGE_STEP,
                NEW_POC_LEVEL_DECREASE_MULTIPLIER_AFTER_TREND,
                NEW_POC_PROFIT_PERCENTAGE,
                offsetJettons,
                NEW_POC_CONTROL_PERIOD,
                NEW_POC_JETTON_SUPPORT,
                supportJetton.address,
                NEW_POC_ROYALTY_PROFIT_PERCENT,
                NEW_POC_COEFFICIENT_PROFIT,
                NEW_POC_JETTON_DECIMALS,
            ),
        );

        const deployNewPocResult = await newPocContract.send(
            deployer.getSender(),
            {
                value: toNano('1'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            },
        );

        expect(deployNewPocResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: newPocContract.address,
            deploy: true,
            success: true,
        });

        await verifyTransactions(deployNewPocResult.transactions, deployer.address);


        const deployedOwner = await newPocContract.getOwnerAddress();
        const deployedLaunchJettonMaster = await newPocContract.getJettonMasterAddress();
        const deployedReturnWallet = await newPocContract.getReturnWalletAddress();
        const deployedLockEndTime = await newPocContract.getLockEndTime();
        const deployedOffsetJettons = await newPocContract.getOffsetJettons();
        const deployedControlPeriod = await newPocContract.getControlPeriod();
        const deployedJettonSupport = await newPocContract.getIsJettonCollateral();
        const deployedJettonCollateralMaster = await newPocContract.getJettonCollateralMasterAddress();
        const deployedRoyaltyProfitPercent = await newPocContract.getRoyaltyProfitPercent();

        console.log(offsetJettons.toString());

        expect(deployedOwner.toString()).toBe(owner.address.toString());
        expect(deployedLaunchJettonMaster.toString()).toBe(launchJetton.address.toString());
        expect(deployedReturnWallet.toString()).toBe(owner.address.toString());
        expect(deployedLockEndTime).toBe(newLockEndTime);
        expect(deployedOffsetJettons).toBe(offsetJettons);
        expect(deployedControlPeriod).toBe(NEW_POC_CONTROL_PERIOD);
        expect(deployedJettonSupport).toBe(NEW_POC_JETTON_SUPPORT);
        expect(deployedJettonCollateralMaster.toString()).toBe(supportJetton.address.toString());
        expect(deployedRoyaltyProfitPercent).toBe(NEW_POC_ROYALTY_PROFIT_PERCENT);

        const setOldContractResult = await newPocContract.send(
            owner.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'OldContractAddress',
                oldContractAddress: proofOfCapital.address,
            },
        );

        expect(setOldContractResult.transactions).toHaveTransaction({
            from: owner.address,
            to: newPocContract.address,
            success: true,
        });

        await verifyTransactions(setOldContractResult.transactions, owner.address);

        const currentTime = Math.floor(Date.now() / 1000);
        const lockEndTime = await proofOfCapital.getLockEndTime();
        const timeToAdvance = Number(lockEndTime) - currentTime - 60 * 24 * 3600 + 3600;

        if (timeToAdvance > 0) {
            blockchain.now = currentTime + timeToAdvance;
        } else {
            blockchain.now = currentTime + 60 * 24 * 3600 + 3600;
        }

        console.log('Advanced time by:', timeToAdvance, 'seconds');
        console.log('Current blockchain time:', blockchain.now);
        console.log('Lock end time:', lockEndTime.toString());

        const collateralDeferredWithdrawalResult = await proofOfCapital.send(
            owner.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'CollateralDeferredWithdrawal',
                recipientAddress: newPocContract.address,
            },
        );

        const launchDeferredWithdrawalResult = await proofOfCapital.send(
            owner.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'JettonDeferredWithdrawal',
                recipientAddress: newPocContract.address,
                amount: toNano('100000'),
            },
        );

        expect(collateralDeferredWithdrawalResult.transactions).toHaveTransaction({
            from: owner.address,
            to: proofOfCapital.address,
            success: true,
        });

        expect(launchDeferredWithdrawalResult.transactions).toHaveTransaction({
            from: owner.address,
            to: proofOfCapital.address,
            success: true,
        });

        const THIRTY_DAYS = 2_592_000;
        blockchain.now = blockchain.now + THIRTY_DAYS + 3600;

        await newPocContract.send(
            owner.getSender(),
            { value: toNano('100'), bounce: false },
            {
                $$type: 'Deploy',
                queryId: 0n,
            },
        );

        const confirmLaunchWithdrawalResult = await proofOfCapital.send(
            owner.getSender(),
            { value: toNano('1.5') },
            {
                $$type: 'ConfirmJettonDeferredWithdrawal',
            },
        );
        const confirmCollateralWithdrawalResult = await proofOfCapital.send(
            owner.getSender(),
            { value: toNano('1.5') },
            {
                $$type: 'ConfirmCollateralDeferredWithdrawal',
            },
        );

        expect(confirmCollateralWithdrawalResult.transactions).toHaveTransaction({
            from: owner.address,
            to: proofOfCapital.address,
            success: true,
        });

        expect(confirmLaunchWithdrawalResult.transactions).toHaveTransaction({
            from: owner.address,
            to: proofOfCapital.address,
            success: true,
        });

        await verifyTransactions(confirmLaunchWithdrawalResult.transactions, owner.address, proofOfCapital.address);
        expect(confirmCollateralWithdrawalResult.transactions).toHaveTransaction({
            to: newPocContract.address,
            success: false,
            exitCode: -14,
        });
    });
});
