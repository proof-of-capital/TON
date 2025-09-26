import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/jetton/my_jetton.tact',
    options: {
        debug: true,
    },
};
