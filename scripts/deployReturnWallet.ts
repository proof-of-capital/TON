import { toNano } from '@ton/core';
import { ReturnWallet } from '../wrappers/ReturnWallet';
import { NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const returnWallet = provider.open(await ReturnWallet.fromInit());

    await returnWallet.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(returnWallet.address);

    // run methods on `returnWallet`
}
