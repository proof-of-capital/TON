import { Address, toNano } from '@ton/core';
import { ReturnWallet } from '../wrappers/ReturnWallet';
import { NetworkProvider } from '@ton/blueprint';

//npx blueprint run deployReturnWallet --testnet --mnemonic
export async function run(provider: NetworkProvider) {
    let launchJettonMasterAddress = 'EQC8Xo9n7sHj2mLh3u5Zt1v6z5c5s5s5s5s5s5s5s5s5s5s5s5s5s5';
    let mmAddress = 'EQC8Xo9n7sHj2mLh3u5Zt1v6z5c5s5s5s5s5s5s5s5s5s5s5s5s5s5';
    const returnWallet = provider.open(
        await ReturnWallet.fromInit(Address.parse(launchJettonMasterAddress), Address.parse(mmAddress)),
    );

    await returnWallet.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        },
    );

    await provider.waitForDeploy(returnWallet.address);

    // run methods on `returnWallet`
}
