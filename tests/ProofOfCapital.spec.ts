import { Blockchain, internal, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { beginCell, toNano, fromNano, Transaction, Address, ExternalAddress } from '@ton/core';
import { ProofOfCapital } from '../wrappers/ProofOfCapital';
import { JettonUpdateContent } from '../wrappers/TestJetton_JettonMinter';
import { ExtendedJettonMinter } from '../wrappers/ExtendedJettonMinter';
import { ExtendedJettonWallet } from '../wrappers/ExtendedJettonWallet';
import { flattenTransaction } from '@ton/test-utils';
import '@ton/test-utils';

// TODO: Initialize the contract without the Jetton collateral and test its
//       functionality. It could be done in the second test file for convinience.
//
// TODO: Check out-of-gas issues in `receive()`. We are interested in these formulas:
//       https://github.com/proof-of-capital/TON/blob/137d44bbc649745f8cff864c8cad9db47bd70f26/contracts/proof_of_capital.tact#L605.
//       The goal there is to set different state values (e.g.
//       self.comission, self.quantityJettonsPerLevel) and different message
//       values in order to test if it works.
//
// TODO: Test various functions involving the `isInitialized` and `isActive`
//       conditions. The first condition could be checked in the initialization
//       of the test suite, before sending the `TakeWalletAddress` message.
//
// TODO: Test the oldContractAddress usage scenarios.
//
// TODO: Test the migration process:
//       1. Deploy two PoC contracts
//       2. Add some collateral and issues tokens on the first one
//       3. Freeze it, deactivate, and move tokens to the second one
//       4. Ensure the offsets and steps on both contracts are equal

// https://github.com/ton-org/sandbox/blob/24ad00977d3abb99ee027149acee1ab11a162bab/src/utils/prettyLogTransaction.ts#L5
export type AddressMapFunc = (address: Address | ExternalAddress | null | undefined) => string | null | undefined;

// Initial jettons balance
const JETTONS_BALANCE = 10_000_000_000n;

/**
 * A helper function to access the jetton wallet from the given address.
 */
type JettonWalletCaller = (address: Address) => Promise<SandboxContract<ExtendedJettonWallet>>;

describe.each([false, true])('ProofOfCapital (JETTON_COLLATERAL=%s)', (JETTON_COLLATERAL) => {
    let blockchain: Blockchain;
    let poc: SandboxContract<ProofOfCapital>;
    let pocDeployer: SandboxContract<TreasuryContract>;
    let marketMaker: SandboxContract<TreasuryContract>;
    let launchMinter: SandboxContract<ExtendedJettonMinter>;
    let launchDeployer: SandboxContract<TreasuryContract>;
    let launchDeployerWallet: SandboxContract<ExtendedJettonWallet>;
    let launchPocWallet: SandboxContract<ExtendedJettonWallet>;
    let launchUserWallet: JettonWalletCaller;
    let collateralMinter: SandboxContract<ExtendedJettonMinter>;
    let collateralDeployer: SandboxContract<TreasuryContract>;
    let collateralDeployerWallet: SandboxContract<ExtendedJettonWallet>;
    let collateralPocWallet: SandboxContract<ExtendedJettonWallet>;
    let collateralUserWallet: JettonWalletCaller;

    beforeAll(async () => {
        blockchain = await Blockchain.create();
        // Initialize jettons used by the contract
        launchDeployer = await blockchain.treasury('launchDeployer');
        launchMinter = await deployMinter(launchDeployer);
        [launchDeployerWallet, launchUserWallet] = await deployWallet(launchDeployer, launchMinter);
        if (JETTON_COLLATERAL) {
            // Collater jetton is optional. It could be used instead of TON if
            // the PoC contract is configured that way.
            collateralDeployer = await blockchain.treasury('jettonCollateralDeployer');
            collateralMinter = await deployMinter(collateralDeployer);
            [collateralDeployerWallet, collateralUserWallet] = await deployWallet(collateralDeployer, collateralMinter);
        }
        // Initialize the poc contract
        marketMaker = await blockchain.treasury('marketMaker');
        pocDeployer = await blockchain.treasury('deployer');
        poc = blockchain.openContract(
            await ProofOfCapital.fromInit(
                /*id=*/ 0n,
                /*owner=*/ pocDeployer.address,
                /*marketMakerAddress=*/ marketMaker.address,
                /*launchMasterAddress=*/ launchMinter.address,
                /*returnWalletAddress=*/ pocDeployer.address,
                /*royaltyWalletAddress=*/ pocDeployer.address,
                /*lockEndTime=*/ BigInt(Math.floor(Date.now() / 1000)),
                /*initialPricePerToken=*/ 15000n,
                /*firstLevelJettonQuantity=*/ toNano(5000000n),
                /*priceIncrementMultiplier=*/ 50n,
                /*levelIncreaseMultiplier=*/ 20n,
                /*trendChangeStep=*/ 20n,
                /*levelDecreaseMultiplierafterTrend=*/ 9n,
                /*profitPercentage=*/ 100n /*10%*/,
                /*offsetJettons=*/ toNano(15000n),
                /*controlPeriod=*/ 60n,
                /*jettonCollateral=*/ JETTON_COLLATERAL,
                /*jettonCollateralMasterAddress=*/ JETTON_COLLATERAL ? collateralMinter.address : pocDeployer.address,
                /*royaltyProfitPercent=*/ 200n,
                /*coefficientProfit=*/ 200n,
                /*jettonDecimals=*/ toNano(1n),
            ),
        );
        const deployResult = await poc.send(
            pocDeployer.getSender(),
            { value: toNano('0.1') },
            { $$type: 'Deploy', queryId: 0n },
        );
        expect(deployResult.transactions).toHaveTransaction({
            from: pocDeployer.address,
            to: poc.address,
            deploy: true,
            success: true,
        });

        // Save jetton wallets owned by the PoC contract
        launchPocWallet = await launchUserWallet(poc.address);
        expect(launchPocWallet.address.toString()).toBe((await poc.getJettonWalletAddress()).toString());
        if (JETTON_COLLATERAL) {
            collateralPocWallet = await collateralUserWallet(poc.address);
            expect(collateralPocWallet.address.toString()).toBe(
                (await poc.getContractJettonCollateralWalletAddress()).toString(),
            );
        }
    });

    async function deployMinter(
        deployer: SandboxContract<TreasuryContract>,
    ): Promise<SandboxContract<ExtendedJettonMinter>> {
        const defaultContent = beginCell().endCell();
        const msg: JettonUpdateContent = {
            $$type: 'JettonUpdateContent',
            queryId: 0n,
            content: defaultContent,
        };
        const minter = blockchain.openContract(
            await ExtendedJettonMinter.fromInit(0n, deployer.address, defaultContent),
        );
        const result = await minter.send(deployer.getSender(), { value: toNano('0.1') }, msg);
        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: minter.address,
            deploy: true,
            success: true,
        });
        return minter;
    }

    async function deployWallet(
        deployer: SandboxContract<TreasuryContract>,
        minter: SandboxContract<ExtendedJettonMinter>,
    ): Promise<[SandboxContract<ExtendedJettonWallet>, JettonWalletCaller]> {
        const wallet = blockchain.openContract(
            await ExtendedJettonWallet.fromInit(deployer.address, minter.address, 0n),
        );
        const userWallet = async (address: Address) => {
            return blockchain.openContract(new ExtendedJettonWallet(await minter.getGetWalletAddress(address)));
        };
        return [wallet, userWallet];
    }

    /**
     * Executes the mint functions of the jetton called by its master.
     * This results in minting `jettons` to its wallet.
     */
    async function mintJettons(
        jettonDeployer: SandboxContract<TreasuryContract>,
        master: SandboxContract<ExtendedJettonMinter>,
        deployerWallet: SandboxContract<ExtendedJettonWallet>,
        jettonsMintAmount: bigint,
    ) {
        const supplyBefore = await master.getTotalSupply();
        const result = await master.sendMint(
            jettonDeployer.getSender(),
            jettonDeployer.address,
            jettonsMintAmount,
            toNano('0.05'),
            toNano('1'),
        );
        expect(result.transactions).toHaveTransaction({
            from: master.address,
            to: deployerWallet.address,
            deploy: true,
        });
        const supplyAfter = await master.getTotalSupply();
        expect(supplyBefore + jettonsMintAmount === supplyAfter).toBe(true);
    }

    /**
     * Transfers jettons from the sender's wallet to the wallet owned by `receiver`.
     *
     * The total supply of minted jettons (see `mintJettons`) must be sufficient,
     * as well as the sender's jetton balance.
     *
     * @param receiver The address of the jetton receiver. This must be the exact
     * contract or user address (NOT the address of their jetton wallet).
     */
    async function transferJettons(
        senderWalletOwner: SandboxContract<TreasuryContract>,
        senderWallet: SandboxContract<ExtendedJettonWallet>,
        receiver: Address,
        jettonsAmount: bigint,
    ) {
        const senderBalanceBefore = await senderWallet.getJettonBalance();
        expect(senderBalanceBefore).toBeGreaterThanOrEqual(jettonsAmount);
        const receiverWallet = await launchUserWallet(receiver);
        const receiverBalanceBefore = await receiverWallet.getJettonBalance();
        await senderWallet.sendTransfer(
            senderWalletOwner.getSender(),
            toNano('0.5'),
            jettonsAmount,
            receiver,
            senderWalletOwner.address,
            null,
            0n,
            null,
        );
        const senderBalanceAfter = await senderWallet.getJettonBalance();
        const receiverBalanceAfter = await receiverWallet.getJettonBalance();
        expect(senderBalanceBefore - jettonsAmount).toBe(senderBalanceAfter);
        expect(receiverBalanceBefore + jettonsAmount).toBe(receiverBalanceAfter);
    }

    /**
     * Implements the same logic as `transferJettons`, but uses the PoC contract
     * instead of the TEP74 compatible jetton wallet.
     */
    async function transferPocJettons(
        senderWalletOwner: SandboxContract<TreasuryContract>,
        senderWallet: SandboxContract<ExtendedJettonWallet>,
        jettonsAmount: bigint,
    ) {
        const senderBalanceBefore = await senderWallet.getJettonBalance();
        expect(senderBalanceBefore).toBeGreaterThanOrEqual(jettonsAmount);
        const pocBalanceBefore = await poc.getJettonBalance();
        const result = await senderWallet.sendTransfer(
            senderWalletOwner.getSender(),
            toNano('0.5'),
            jettonsAmount,
            poc.address,
            senderWalletOwner.address,
            null,
            0n,
            null,
        );
        console.log(ppTxes(result.transactions));
        const senderBalanceAfter = await senderWallet.getJettonBalance();
        const pocBalanceAfter = await poc.getJettonBalance();
        expect(senderBalanceBefore - jettonsAmount).toBe(senderBalanceAfter);
        expect(pocBalanceBefore + jettonsAmount).toBe(pocBalanceAfter);
    }

    // ----------------------------------------------------
    // Tests
    // ----------------------------------------------------

    it('should deploy', async () => {
        expect(poc).toBeDefined();
        expect(launchMinter).toBeDefined();
        expect(launchDeployerWallet).toBeDefined();
        expect(launchUserWallet).toBeDefined();
        expect(launchPocWallet).toBeDefined();
        await mintJettons(launchDeployer, launchMinter, launchDeployerWallet, JETTONS_BALANCE);
        if (JETTON_COLLATERAL) {
            expect(collateralMinter).toBeDefined();
            expect(collateralDeployerWallet).toBeDefined();
            expect(collateralUserWallet).toBeDefined();
            expect(collateralPocWallet).toBeDefined();
            await mintJettons(collateralDeployer, collateralMinter, collateralDeployerWallet, JETTONS_BALANCE);
        }
    });

    it('should accept TONs from owner via receive()', async () => {
        if (!JETTON_COLLATERAL) return;
        const sentTons = toNano('10');
        const expectedCommission = toNano('0.1');
        const tonBalanceBefore = await poc.getBalance();
        await poc.send(pocDeployer.getSender(), { value: sentTons }, null);
        const tonBalanceAfter = await poc.getBalance();
        expect(tonBalanceAfter - expectedCommission > tonBalanceBefore);
    });

    // ----------------------------------------------------
    // Utility funcitons for debugging
    // ----------------------------------------------------

    function replaceAddresses(str: string): string {
        const replaceMany = (str: string, ...pairs: Array<[string, string]>): string => {
            const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            const lookup: Record<string, string> = Object.fromEntries(pairs);
            const pattern = new RegExp(
                pairs
                    .map(([k]) => escape(k))
                    .sort((a, b) => b.length - a.length)
                    .join('|'),
                'g',
            );
            return str.replace(pattern, (m) => lookup[m]!);
        };
        return replaceMany(
            str,
            [poc.address.toString(), 'poc'],
            [pocDeployer.address.toString(), 'pocDeployer'],
            [marketMaker.address.toString(), 'marketMaker'],
            [launchMinter.address.toString(), 'launchMinter'],
            [launchDeployer.address.toString(), 'launchDeployer'],
            [launchDeployerWallet.address.toString(), 'launchWallet'],
            [launchPocWallet.address.toString(), 'launchPocWallet'],
            [collateralMinter ? collateralMinter.address.toString() : 'collateralMaster', 'collateralMaster'],
            [
                collateralDeployer ? collateralDeployer.address.toString() : 'jettonCollateralDeployer',
                'collateralDeployer',
            ],
            [
                collateralDeployerWallet ? collateralDeployerWallet.address.toString() : 'collateralWallet',
                'collateralWallet',
            ],
            [
                collateralPocWallet ? collateralPocWallet.address.toString() : 'collateralPocWallet',
                'collateralPocWallet',
            ],
        );
    }
    function ppTx(tx: Transaction, mapFunc?: AddressMapFunc) {
        const mapAddress = (address: Address | ExternalAddress | null | undefined) => {
            return mapFunc ? (mapFunc(address) ?? address) : address;
        };
        const flatTx = flattenTransaction(tx);
        let res = '';
        const info = tx.inMessage?.info;
        if (info) {
            switch (info.type) {
                case 'internal':
                    res = `${mapAddress(info.src)} ➡️ ${mapAddress(info.dest)}\n  [internal]`;
                    break;
                case 'external-in':
                    res = `${info.src ? mapAddress(info.src) : '???'} ➡️ ${mapAddress(info.dest)}\n  [external/in]`;
                    break;
                case 'external-out':
                    res = `${mapAddress(info.src)} ➡️ ${info.dest ? mapAddress(info.dest) : '???'}\n  [external/out]`;
                    break;
            }
        }
        const success = ('actionPhase' in tx.description ? tx.description.actionPhase : undefined)?.success;
        if (success !== undefined) {
            if (success === true) {
                res += ' [✅]';
            } else if (success === false) {
                res += ' [❌]';
            }
        }
        if (flatTx.op !== undefined) {
            res += ` [op=${'0x' + flatTx.op.toString(16)}]`;
        }
        res += '\n';
        for (let message of tx.outMessages.values()) {
            const dest = mapAddress(message.info.dest);
            if (message.info.type === 'internal') {
                res += `  out: ${fromNano(message.info.value.coins)}💎 ${dest}\n`;
            } else {
                res += `  out: ${dest}\n`;
            }
        }
        return res;
    }
    function ppTxes(txs: Transaction[], mapFunc?: AddressMapFunc): string {
        let out = '';
        for (let tx of txs) {
            out += replaceAddresses(ppTx(tx, mapFunc)) + '\n';
        }
        return out;
    }
    function ppBi(bi: bigint) {
        return bi.toString().replace(/\B(?=(\d{3})+(?!\d))/g, '_');
    }
    function ppKnownContracts(): string {
        return (
            blockchain.snapshot().contracts.length,
            replaceAddresses(
                blockchain.snapshot().contracts.reduce((acc, c) => {
                    return acc + c.address.toString() + '\n';
                }, ''),
            )
        );
    }
});
