import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/proof_of_capital.tact',
    options: {
        debug: true,
    },
};
