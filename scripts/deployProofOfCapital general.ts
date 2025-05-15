import { Address, toNano, beginCell, Cell} from '@ton/core';
import { ProofOfCapital } from '../wrappers/ProofOfCapital';
import { NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const owner = Address.parse("");
    const marketMaker = Address.parse("");
    const jettonMasterAddress = Address.parse(""); 
    const returnWalletAddress = Address.parse("");
    const royaltyWalletAddress = Address.parse("");
    const lockEndTime = BigInt(Math.floor(Date.now() / 1000));
    const initialPricePerToken = 15000n;
    const firstLevelJettonQuantity = 5000000000000000n;
    const priceIncrementMultiplier = 50n;
    const levelIncreaseMultiplier = 20n;
    const trendChangeStep = 20n;
    const levelDecreaseMultiplierafterTrend = 9n;
    const profitPercentage = 100n;
    const offsetJettons = 15000000000000n;
    const controlPeriod = 60n;
    const jettonSupport = true;
    const jettonSupportMaster = Address.parse("");
    const royaltyProfitPercent = 2n;

    console.log("-------")
    console.log(lockEndTime)

    let proofOfCapital
    // do {
      let id = BigInt(Math.floor(Math.random() * 1000000000));

      proofOfCapital = provider.open(await ProofOfCapital.fromInit(
        id,
        owner,
        marketMaker,
        jettonMasterAddress,
        returnWalletAddress,
        royaltyWalletAddress,
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
        jettonSupportMaster,
        royaltyProfitPercent)
      );
      console.log(id)
      console.log(proofOfCapital.address.toString())
      console.log()
    // } while(!proofOfCapital.address.toString().match(/(A|_P0K|-P0K|_POK|-POK)$/))
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
