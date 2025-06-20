import { toNano } from '@ton/core';
import { ProofOfCapital } from '../wrappers/ProofOfCapital';
import { NetworkProvider } from '@ton/blueprint';
import * as address from './!allAddresses';

export async function run(provider: NetworkProvider) {
    const lockEndTime = BigInt(Math.floor(Date.now() / 1000));
    const initialPricePerToken = 15000n;
    const firstLevelJettonQuantity = toNano(5000000n);
    const priceIncrementMultiplier = 50n;
    const levelIncreaseMultiplier = 20n;
    const trendChangeStep = 20n;
    const levelDecreaseMultiplierafterTrend = 9n;
    const profitPercentage = 100n;
    const offsetJettons = toNano(15000n);
    const controlPeriod = 60n;
    const jettonSupport = true;
    const royaltyProfitPercent = 200n;

    console.log("-------")
    console.log(lockEndTime)

    let proofOfCapital
    // do {
      let id = BigInt(Math.floor(Math.random() * 1000000000));

      proofOfCapital = provider.open(await ProofOfCapital.fromInit(
        id,
        address.owner,
        address.marketMaker,
        address.jettonMasterAddress,
        address.returnWalletAddress,
        address.royaltyWalletAddress,
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
        address.jettonSupportMaster,
        royaltyProfitPercent)
      );
      console.log(id)
      console.log(proofOfCapital.address.toString())
      console.log()
    // } while(!proofOfCapital.address.toString().match(/(A|B)$/))
    await proofOfCapital.send(
        provider.sender(),
        {
            value: toNano('0.06'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

      await provider.waitForDeploy(proofOfCapital.address);

}
