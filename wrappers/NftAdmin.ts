import { Address, beginCell, Cell, Contract, ContractProvider, toNano, Sender, SendMode, Slice, ExtraCurrency } from '@ton/core';
import { Ops } from './Constants';

type OptionsWithdrawSpecific = {
        withdrawSpecific: true,
        curId: number,
}

type OptionsWithdrawAll = {
    withdrawSpecific: false
}

type WithdrawOptions = {
    queryId?: bigint,
    value?: bigint
    fromBalance?: bigint
} & (OptionsWithdrawSpecific | OptionsWithdrawAll);

export class MinterNFTAdmin implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new MinterNFTAdmin(address);
    }

    static transferMessage(jetton_amount: bigint, to: Address,
                           responseAddress:Address | null,
                           customPayload: Cell | null,
                           forward_ton_amount: bigint,
                           forwardPayload?: Cell | Slice | null) {

        const byRef   = forwardPayload instanceof Cell;
        const transferBody = beginCell().storeUint(Ops.OP_MINT_EC, 32).storeUint(0, 64) // op, queryId
                          .storeVarUint(jetton_amount, 5)
                          .storeAddress(to)
                          .storeAddress(responseAddress)
                          .storeMaybeRef(customPayload)
                          .storeCoins(forward_ton_amount)
                          .storeBit(byRef);

        if(byRef) {
            transferBody.storeRef(forwardPayload);
        }
        else if(forwardPayload) {
            transferBody.storeSlice(forwardPayload);
        }
        return transferBody.endCell();
    }

    async sendTransfer(provider: ContractProvider, via: Sender,
                       value: bigint,
                       jetton_amount: bigint, to: Address,
                       responseAddress:Address | null,
                       customPayload: Cell | null,
                       forward_ton_amount: bigint,
                       forwardPayload?: Cell | Slice | null) {
        await provider.internal(via, {
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: MinterNFTAdmin.transferMessage(jetton_amount, to, responseAddress, customPayload, forward_ton_amount, forwardPayload),
            value:value
        });
    }

    static withdrawExcessECMessage(withdrawSpecific: boolean, to: Address, curId: number, fromBalance: bigint = 0n, queryId: bigint | number = 0) {
        const head =  beginCell()
                        .storeUint(Ops.OP_WITHDRAW_EXTRA, 32)
                        .storeUint(queryId, 64)
                        .storeBit(withdrawSpecific);
        if(withdrawSpecific) {
            head.storeUint(curId, 32);
        }
        return head.storeAddress(to).storeCoins(fromBalance).endCell();
    }

    async sendWithdrawExcessEC(provider: ContractProvider, via: Sender, to: Address, opts: WithdrawOptions) {
        let curId = 0;
        let fromBalance = opts.fromBalance ?? 0n;
        if(opts.withdrawSpecific) {
            curId = opts.curId;
        }
        await provider.internal(via, {
            value: opts.value ?? toNano('0.05'),
            body: MinterNFTAdmin.withdrawExcessECMessage(opts.withdrawSpecific, to, curId, fromBalance, opts.queryId ?? 0),
            sendMode: SendMode.PAY_GAS_SEPARATELY
        });
    }

    static rebalanceMessage(queryId: number | bigint = 0) {
        return beginCell()
                .storeUint(Ops.OP_REBALANCE, 32)
                .storeUint(queryId, 64)
               .endCell();
    } 
    async sendRebalance(provider: ContractProvider, via: Sender, value: bigint = toNano('0.05'), queryId: number | bigint = 0) {
        await provider.internal(via, {
            value,
            body: MinterNFTAdmin.rebalanceMessage(queryId),
            sendMode: SendMode.PAY_GAS_SEPARATELY
        });
    }



    static burnMessage(forwardTon: bigint, refund: Address | null = null, customPayload?: Cell, queryId: number | bigint = 0) {
        return beginCell().storeUint(Ops.OP_BURN_EC, 32)
                          .storeUint(queryId, 64)
                          .storeCoins(forwardTon)
                          .storeAddress(refund)
                          .storeMaybeRef(customPayload)
               .endCell();

    }
    async sendBurn(provider: ContractProvider, via: Sender, extra: ExtraCurrency, forwardTon: bigint, refund: Address | null = null, customPayload?:Cell, value: bigint = toNano('0.05'), queryId: bigint | number = 0) {
        await provider.internal(via, {
            extracurrency: extra,
            value,
            body: MinterNFTAdmin.burnMessage(forwardTon, refund, customPayload, queryId),
            sendMode: SendMode.PAY_GAS_SEPARATELY
        });
    }

    async getNftData(provider: ContractProvider) {
        const { stack } = await provider.get('get_nft_data', []);

        return {
            isInit: stack.readBoolean(),
            index: stack.readNumber(),
            collection: stack.readAddress(),
            owner: stack.readAddressOpt(),
            content: stack.readCellOpt()
        }
    }

    async getJettonData(provider: ContractProvider) {
        const { stack } = await provider.get('get_jetton_data', []);

        return {
            supply: stack.readBigNumber(),
            mintable: stack.readBoolean(),
            owner: stack.readAddress(),
            content: stack.readCell(),
            wallet_code: stack.readCellOpt()
        }
    }

    async getDataExtended(provider: ContractProvider) {
        const { stack } = await provider.get('get_extended_data', []);

        return {
            status: stack.readNumber(),
            index: stack.readNumber(),
            collection: stack.readAddress(),
            owner: stack.readAddressOpt(),
            content: stack.readCellOpt(),
            balance: stack.readBigNumber(),
            maxSupply: stack.readBigNumber()
        }
    }
}
