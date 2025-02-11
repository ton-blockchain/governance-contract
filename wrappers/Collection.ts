import { Address, beginCell, Cell, Contract, contractAddress, ContractProvider, toNano, Sender, SendMode, Dictionary, DictionaryValue } from '@ton/core';
import { sha256_sync } from '@ton/crypto';
import { Ops } from './Constants';
import { MinterNFTAdmin } from './NftAdmin';

type CollectionContentOffchain = {
    type: 'offchain',
    uri: string
}
type OnChainContentData = 'uri' | 'name' | 'description' | 'image' | 'image_data' | 'symbol' | 'decimals' | 'amount_style' | 'render_type' | 'currency' | 'game';

type CollectionContentOnchain = {
    type: 'onchain',
    data: Partial<Record<OnChainContentData, string>>
}

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


export type CollectionContent = CollectionContentOnchain | CollectionContentOffchain;
export type ItemContent = CollectionContent;

type CollectionConfig = {
    content: CollectionContent
}

type NewNftItem = {
    index: number,
    owner: Address,
    maxSupply: bigint,
    refund?: Address,
    content: ItemContent
}

function OnChainString(): DictionaryValue<string> {
    return {
        serialize(src, builder) {
            builder.storeRef(beginCell().storeUint(0, 8).storeStringTail(src));
        },
        parse(src) {
            const sc  = src.loadRef().beginParse();
            const tag = sc.loadUint(8);
            if(tag == 0) {
                return sc.loadStringTail();
            } else if(tag == 1) {
                // Not really tested, but feels like it should work
                const chunkDict = Dictionary.loadDirect(Dictionary.Keys.Uint(32), Dictionary.Values.Cell(), sc);
                return chunkDict.values().map(x => x.beginParse().loadStringTail()).join('');

            } else {
                throw Error(`Prefix ${tag} is not supported yet!`);
            }
        }
    }
}
export function nftContentToCell(content: CollectionContent) {
    if(content.type == 'offchain') {
        return beginCell()
            .storeUint(1, 8)
            .storeStringRefTail(content.uri) //Snake logic under the hood
            .endCell();
    }
    let keySet = new Set(['uri' , 'name' , 'description' , 'image' , 'image_data' , 'symbol' , 'decimals' , 'amount_style' , 'render_type' , 'currency' , 'game']);
    let contentDict = Dictionary.empty(Dictionary.Keys.Buffer(32), OnChainString());

    for (let contentKey in content.data) {
        if(keySet.has(contentKey)) {
            contentDict.set(
                sha256_sync(contentKey),
                content.data[contentKey as OnChainContentData]!
            );
        }
    }
    return beginCell().storeUint(0, 8).storeDict(contentDict).endCell();
}

function collectionConfigToCell(config: CollectionConfig) {
    return beginCell().storeUint(0, 32).storeRef(nftContentToCell(config.content)).endCell();
}


export class MinterNFTCollection implements Contract {
    static collectionVersion: number = 0;

    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new MinterNFTCollection(address);
    }

    static createFromConfig(config: CollectionConfig, code: Cell, workchain = 0) {
        const data = collectionConfigToCell(config);
        const init = { code, data };
        return new MinterNFTCollection(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
        });
    }

    static newItemMessage(item: NewNftItem, value: bigint, queryId: number | bigint = 0) {
        let nftContent = beginCell()
                           .storeUint(Ops.OP_MINT_INITIAL, 32)
                           .storeUint(queryId, 64)
                           .storeUint(MinterNFTCollection.collectionVersion, 8)
                           .storeAddress(item.owner)
                           .storeVarUint(item.maxSupply, 5)
                           .storeAddress(item.refund)
                           .storeRef(nftContentToCell(item.content))
                         .endCell();

        return beginCell()
                .storeUint(1, 32) // Op deploy
                .storeUint(queryId, 64)
                .storeUint(item.index, 32)
                .storeCoins(value)
                .storeRef(nftContent)
               .endCell();
    }

    async sendNewItem(provider: ContractProvider, via: Sender, item: NewNftItem, value: bigint = toNano('3'), queryId: bigint | number = 0) {

        await provider.internal(via, {
            value: value + toNano('0.01'),
            body: MinterNFTCollection.newItemMessage(item, value, queryId),
            sendMode: SendMode.PAY_GAS_SEPARATELY
        });
    }

    static withdrawExcessECMessage(withdrawSpecific: boolean, to: Address, curId: number, fromBalance: bigint = 0n, queryId: bigint | number = 0) {
        const head =  beginCell()
                        .storeUint(Ops.OP_WITHDRAW_EXTRA_COLLECTION, 32)
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
            body: MinterNFTCollection.withdrawExcessECMessage(opts.withdrawSpecific, to, curId, fromBalance, opts.queryId ?? 0),
            sendMode: SendMode.PAY_GAS_SEPARATELY
        });
    }

    static updateContentMessage(index: number,
                                content: ItemContent | Cell,
                                refundAddress: Address | null = null,
                                queryId: bigint | number = 0) {

        let contentCell = content instanceof Cell ? content : nftContentToCell(content);

        return beginCell()
                .storeUint(Ops.OP_UPDATE_CONTENT, 32)
                .storeUint(queryId, 64)
                .storeUint(index, 32)
                .storeAddress(refundAddress)
                .storeRef(contentCell)
              .endCell();
    }

    async sendUpdateContent(provider: ContractProvider,
                            via: Sender,
                            index: number,
                            content: ItemContent | Cell,
                            refundAddress: Address | null = null,
                            value: bigint = toNano('0.05'),
                            queryId: bigint | number = 0) {

        await provider.internal(via,{
            value,
            body: MinterNFTCollection.updateContentMessage(index, content, refundAddress, queryId),
            sendMode: SendMode.PAY_GAS_SEPARATELY
        });
    }

    static resetItemMessage(index: number, refundAddress: Address | null = null, queryId: bigint | number = 0) {
        return beginCell()
                .storeUint(Ops.OP_RESET, 32)
                .storeUint(queryId, 64)
                .storeUint(index, 32)
                .storeAddress(refundAddress)
              .endCell();
    }

    async sendResetItem(provider: ContractProvider,
                        via: Sender,
                        index: number,
                        refundAddress: Address | null = null,
                        value: bigint = toNano('0.05'),
                        queryId: bigint | number = 0) {
        await provider.internal(via, {
            value,
            body: MinterNFTCollection.resetItemMessage(index, refundAddress, queryId),
            sendMode: SendMode.PAY_GAS_SEPARATELY
        });
    }

    async getNftAddressByIndex(provider: ContractProvider, idx: number | bigint) {
        const { stack } = await provider.get('get_nft_address_by_index', [{type: 'int', value: BigInt(idx)}]);
        return stack.readAddress();
    }

    async getCollectionData(provider: ContractProvider) {
        const { stack } = await provider.get('get_collection_data', []);

        return {
            nextItemIndex : stack.readNumber(),
            collectionContent: stack.readCell(),
            owner: stack.readAddress()
        };
    }
    
    async getCollectionDataExtended(provider: ContractProvider) {
        const { stack } = await provider.get('get_collection_data_extended', []);

        return {
            version: stack.readNumber(),
            owner: stack.readAddress(),
            itemCount: stack.readNumber(),
            itemMax: stack.readNumber(),
            content: stack.readCell(),
            itemCode: stack.readCell()
        }
    }
}
