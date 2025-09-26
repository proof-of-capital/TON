import { Address } from '@ton/core';
// Helper function to verify transactions don't have failures
export async function verifyTransactions(transactions: any, ...addresses: Address[]) {
    expect(transactions).not.toHaveTransaction({
        success: false,
        exitCode: (code?: number) => code !== 130,
        to: (a?: Address) => !addresses.some((addr) => a?.toString() === addr.toString()),
    });
}
