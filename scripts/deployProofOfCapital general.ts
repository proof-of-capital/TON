import { Address, toNano, beginCell, Cell} from '@ton/core';
import { ProofOfCapital } from '../wrappers/ProofOfCapital';
import { NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const owner = Address.parse("UQC6l0ZX3YjD7ux6tdHAkZGVmI1OBszhBBNcCWAaRkdoYC1x");
    const marketMaker = Address.parse("UQCbkByV1v1DOu95gMLxXwAivnNwQ7kUp4qkekMQ9FtwErEu");
    const jettonMasterAddress = Address.parse("EQBp6FAkDdHD_lLKUBI-J-Et5zQeyJlixc6f3iKHBie85Fd-");
    const returnWalletAddress = Address.parse("UQCUtOic7l-fD7K2eNhFmmwHNDVs0SAJj5TWbOkQ8l6Fv5BI");
    const royaltyWalletAddress = Address.parse("UQCUtOic7l-fD7K2eNhFmmwHNDVs0SAJj5TWbOkQ8l6Fv5BI");
    const lockEndTime = BigInt(Math.floor(Date.now() / 1000));
    const initialPricePerToken = 15000n;
    const firstLevelJettonQuantity = 5000000000000000n;
    const priceIncrementMultiplier = 50n;
    const levelIncreaseMultiplier = 20n;
    const trendChangeStep = 20n;
    const levelIncreaseMultiplierafterTrend = 9n;
    const profitPercentage = 100n;

    console.log("-------")
    console.log(lockEndTime)

    let proofOfCapital
    do {
      let id = BigInt(Math.floor(Math.random() * 1000000000));

      proofOfCapital = provider.open(await ProofOfCapital.fromInit(
        id,
        owner,
        marketMaker,
        jettonMasterAddress,
        //jetton_data,
        returnWalletAddress,
        royaltyWalletAddress,
        lockEndTime,
        initialPricePerToken,
        firstLevelJettonQuantity,
        priceIncrementMultiplier,
        levelIncreaseMultiplier,
        trendChangeStep,
        levelIncreaseMultiplierafterTrend,
        profitPercentage)
      );
      console.log(id)
      console.log(proofOfCapital.address.toString())
      console.log()
    } while(!proofOfCapital.address.toString().match(/(_P0K|-P0K|_POK|-POK)$/))
    await proofOfCapital.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

      await provider.waitForDeploy(proofOfCapital.address);

}
