import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { toNano } from '@ton/core';
import { ReturnWallet } from '../wrappers/ReturnWallet';
import '@ton/test-utils';

describe('ReturnWallet', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let returnWallet: SandboxContract<ReturnWallet>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        returnWallet = blockchain.openContract(await ReturnWallet.fromInit());

        deployer = await blockchain.treasury('deployer');

        const deployResult = await returnWallet.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: returnWallet.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and returnWallet are ready to use
    });
});
