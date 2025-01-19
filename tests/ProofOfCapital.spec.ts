import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { beginCell, toNano } from '@ton/core';
import { ProofOfCapital } from '../wrappers/ProofOfCapital';
import '@ton/test-utils';
import fc from "fast-check";

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
    let proofOfCapital: SandboxContract<ProofOfCapital>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        marketMaker = await blockchain.treasury('marketMaker');
        jettonMaster = await blockchain.treasury('jettonMaster');
        deployer = await blockchain.treasury('deployer');
        proofOfCapital = blockchain.openContract(
          await ProofOfCapital.fromInit(
            /*id=*/0n,
            /*owner=*/deployer.address,
            /*marketMakerAddress=*/marketMaker.address,
            /*jettonMasterAddress=*/jettonMaster.address,
            /*returnWalletAddress=*/deployer.address,
            /*royaltyWalletAddress=*/deployer.address,
            /*lockEndTime=*/BigInt(Math.floor(Date.now() / 1000)),
            /*initialPricePerToken=*/15000n,
            /*firstLevelJettonQuantity=*/5000000000000000n,
            /*priceIncrementMultiplier=*/50n,
            /*levelIncreaseMultiplier=*/20n,
            /*trendChangeStep=*/20n,
            /*levelIncreaseMultiplierafterTrend=*/9n,
            /*profitPercentage=*/100n/*10%*/,
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

    async function takeAddress() {
        const result = await proofOfCapital.send(
            jettonMaster.getSender(),
            { value: toNano('2') },
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

    async function topupJettons() {
        const jettonSendResult = await proofOfCapital.send(
            jettonMaster.getSender(),
            { value: toNano('2') },
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

    // Ensures that the contract could be deployed
    it('should deploy', async () => {});

    it("get ton_to_jetton_calculation", async () => {
      expect(await proofOfCapital.getTonToJettonCalculation(0n)).toEqual(0n)
      expect(await proofOfCapital.getTonToJettonCalculation(1n)).toEqual(66666n)
      expect(await proofOfCapital.getTonToJettonCalculation(2n)).toEqual(133333n)
      expect(await proofOfCapital.getTonToJettonCalculation(3n)).toEqual(200000n)
      expect(await proofOfCapital.getTonToJettonCalculation(1000n)).toEqual(66666666n)

      // FIXME: This input should be rejected (C1 vuln)
      expect(await proofOfCapital.getTonToJettonCalculation(10000000n)).toEqual(JETTONS_BALANCE)

      expect(await proofOfCapital.getTonToJettonCalculation(-1n)).toEqual(0n)
      expect(await proofOfCapital.getTonToJettonCalculation(-1000000n)).toEqual(0n)
    });

    // Property-based test to ensure non-negative output
    it("get ton_to_jetton_calculation PBT", async () => {
      await fc.assert(
          fc.asyncProperty(
              fc.bigInt({ min: -1000000000000n, max: 1000000000000n }),
              async (input) => {
                  const result = await proofOfCapital.getTonToJettonCalculation(input);
                  return result >= 0n && result <= JETTONS_BALANCE;
              }
          ),
          { numRuns: 100 }
      );
    });

});
