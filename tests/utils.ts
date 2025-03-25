import { Transaction } from '@ton/core';

const getRandom = (min:number, max:number) => {
    return Math.random() * (max - min) + min;
}

export const getRandomInt = (min: number, max: number) => {
    return Math.round(getRandom(min, max));
}

export function computedGeneric<T extends Transaction>(transaction: T) {
    if(transaction.description.type !== "generic")
        throw("Expected generic transactionaction");
    if(transaction.description.computePhase.type !== "vm")
        throw("Compute phase expected")
    return transaction.description.computePhase;
}
