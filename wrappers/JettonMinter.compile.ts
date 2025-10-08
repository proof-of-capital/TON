import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/jetton/base/jetton-minter.tact',
    options: {
        debug: true,
    },
};
