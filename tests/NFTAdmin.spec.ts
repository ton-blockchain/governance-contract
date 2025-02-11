import { Blockchain, BlockchainSnapshot, internal, SandboxContract, TreasuryContract, SmartContract, createShardAccount } from '@ton/sandbox';
import { Address, beginCell, Cell, Dictionary, storeMessage, toNano, fromNano, internal as internal_relaxed, SendMode, StateInit, Sender, contractAddress, DictionaryValue } from '@ton/core';
import '@ton/test-utils';
import { compile } from '@ton/blueprint';
import { MinterNFTCollection, nftContentToCell } from '../wrappers/Collection';
import { MintError, Ops } from '../wrappers/Constants';
import { MinterNFTAdmin } from '../wrappers/NftAdmin';
import { JettonMinter } from './JettonMinter';
import { computedGeneric, getRandomInt } from './utils';
import { executeTill, findTransaction, findTransactionRequired } from '@ton/test-utils';
import { getMsgPrices } from './gasUtils';

type AuthorizationRecord = {
    address: Address,
    wallet: Cell,
    owner: Address,
    maxCount: number
}

function authorizationRecordValue(): DictionaryValue<AuthorizationRecord> {
    return {
        parse: (src) => {
            return {
                address: src.loadAddress(),
                owner: src.loadAddress(),
                maxCount: src.loadUint(32),
                wallet: src.loadRef()
            }
        },
        serialize: (src, builder) => {
            builder.storeAddress(src.address)
                   .storeAddress(src.owner)
                   .storeRef(src.wallet)
                   .storeUint(src.maxCount, 32);
        }
    }
}

describe('NFT Admin', () => {

    let collectionCode: Cell;
    let itemCode: Cell;
    let configCode: Cell;
    let minterCode: Cell;

    let initalState: BlockchainSnapshot;
    let adminMinted: BlockchainSnapshot;
    let mintInProgress: BlockchainSnapshot;
    let coinsMinted: BlockchainSnapshot;

    let mintIdx: number;

    let deployer: SandboxContract<TreasuryContract>;
    let otherWallet: SandboxContract<TreasuryContract>;

    let collection: SandboxContract<MinterNFTCollection>;
    let minterAdmin: SandboxContract<MinterNFTAdmin>;

    let minterAddr: Address;
    let configAddr: Address;

    let blockchain: Blockchain;

    let msgPrices: ReturnType<typeof getMsgPrices>;

    const authConfigId = -0xEC;
    const ecId = 0;
    const COLLECTION_VERSION = 0;
    const maxBtcValue = BigInt(10 ** 8) * 21_000_000n;

    let getNftItem: (index: number) => Promise<SandboxContract<MinterNFTAdmin>>;
    let getEcBalance: (address: Address, idx: number) => Promise<bigint>;
    let getContractData:(address: Address) => Promise<Cell>;

    beforeAll(async () => {
        collectionCode = await compile('Collection');
        itemCode = await compile('NftAdmin');
        configCode = await compile('Config');
        minterCode = await compile('Minter');

        let echoCode = await compile('Echo');

        blockchain = await Blockchain.create();

        deployer    = await blockchain.treasury('deployer');
        otherWallet = await blockchain.treasury('otherWallet');

        msgPrices = getMsgPrices(blockchain.config, 0);

        let configDict = Dictionary.loadDirect(Dictionary.Keys.Int(32), Dictionary.Values.Cell(), blockchain.config);

        configAddr = new Address(-1, Buffer.from(configDict.get(0)!.beginParse().preloadUintBig(256).toString(16), 'hex'));
        minterAddr = Address.parseRaw("-1:c13e44a8368271bcc03590cf609dc8a43e874ba2fde3489cb850727822cba5ad");

        configDict.set(2, beginCell().storeBuffer(minterAddr.hash).endCell());

        // Setting param 6
        const mintFee = toNano('1');
        configDict.set(6, beginCell().storeCoins(mintFee).storeCoins(mintFee).endCell());

        // Allowing extra currency mint
        // const ecDict = Dictionary.empty(Dictionary.Keys.Int(32), Dictionary.Values.BigVarUint(5));
        // ecDict.set(ecId, 0n);
        // configDict.set(7, beginCell().storeDict(ecDict).endCell());

        let echoInit: StateInit = {code: echoCode };

        let echoAddress = contractAddress(0, echoInit);

        await deployer.send({
            to: echoAddress,
            init: echoInit,
            value: toNano('1'),
            bounce: false
        });

        let minterData = beginCell().storeAddress(echoAddress).endCell();

        await blockchain.setShardAccount(minterAddr, createShardAccount({
            address: minterAddr,
            code: minterCode,
            data: minterData,
            balance: toNano('1000')
        }));

        collection = blockchain.openContract(
            MinterNFTCollection.createFromConfig({
                content: {
                    type: 'onchain',
                    data: {
                        name: "Minter admin collection",
                        description: "Collection of extra currency minter admin contracts"
                    }
                }
            }, collectionCode)
        );

        let res = await collection.sendDeploy(deployer.getSender(), toNano('10'));

        expect(res.transactions).toHaveTransaction({
            on: collection.address,
            from: deployer.address,
            aborted: false,
            deploy: true
        });

        getEcBalance = async (address, id) => {
            const smc = await blockchain.getContract(address);
            return smc.ec[id] ?? 0n;
        }

        getNftItem = async (index) => {
            return blockchain.openContract(
                MinterNFTAdmin.createFromAddress(
                    await collection.getNftAddressByIndex(index)
                )
            );
        }

        getContractData = async (address: Address) => {
          const smc = await blockchain.getContract(address);
          if(!smc.account.account)
            throw("Account not found")
          if(smc.account.account.storage.state.type != "active" )
            throw("Atempting to get data on inactive account");
          if(!smc.account.account.storage.state.state.data)
            throw("Data is not present");
          return smc.account.account.storage.state.state.data
        }

        let authConfig = Dictionary.empty(Dictionary.Keys.Uint(8), authorizationRecordValue());

        authConfig.set(0, {
            address: collection.address,
            wallet: itemCode,
            maxCount: 2,
            owner: deployer.address
        });

        const authCell = beginCell().storeDictDirect(authConfig).endCell();
        configDict.set(authConfigId, authCell);

        const configCell = beginCell().storeDictDirect(configDict).endCell();

        await blockchain.setShardAccount(configAddr, createShardAccount({
            address: configAddr,
            code: configCode,
            data: beginCell().storeRef(configCell).storeUint(0, 32).storeUint(0n, 256).storeDict(null).endCell(),
            balance: toNano('1000')
        }));

        blockchain.setConfig(beginCell().storeDictDirect(configDict).endCell());

        // Initializing nft minter admin contract
        minterAdmin = await getNftItem(ecId);

        initalState = blockchain.snapshot();
    });

    it('should deploy', async () => {});

    it('should deploy nft item and mint proper amount of EC', async () => {
        // Intest of emulating full async chain
        // let's pretend currency is already at minter

        let configDict = Dictionary.loadDirect(Dictionary.Keys.Int(32), Dictionary.Values.Cell(), blockchain.config);
        let ecMinted   = Dictionary.load(Dictionary.Keys.Int(32), Dictionary.Values.BigVarUint(5), configDict.get(7)!);

        // Before didn't exists
        expect(ecMinted.get(ecId)).toBeUndefined();


        await blockchain.sendMessage(internal({
            from: deployer.address,
            to: minterAddr,
            value: 0n,
            ec: [[ecId, maxBtcValue]]
        }));

        let smc = await blockchain.getContract(minterAddr);
        expect(smc.ec[0]).toEqual(maxBtcValue);

        let res = await collection.sendNewItem(deployer.getSender(), {
            owner: deployer.address,
            maxSupply: maxBtcValue,
            refund: otherWallet.address,
            index: ecId,
            content: {
                type: 'onchain',
                data: {
                    name: "tgBTC",
                    symbol: "tgBTC",
                    decimals: "9" // Oops
                }
            }
        });

        const mintItemTx = findTransactionRequired(res.transactions,{
            on: collection.address,
            from: deployer.address,
            op: Ops.OP_NEW_ITEM,
            aborted: false,
        });
        console.log("Mint item collection gas:", computedGeneric(mintItemTx).gasUsed);

        const mintInitialTx = findTransactionRequired(res.transactions, {
            on: minterAdmin.address,
            from: collection.address,
            op: Ops.OP_MINT_INITIAL,
            aborted: false
        });

        console.log("Mint initial gas:", computedGeneric(mintInitialTx).gasUsed);

        // console.log(res.transactions);
        //console.log(res.transactions[5].vmLogs);
        const mintedTx = findTransactionRequired(res.transactions, {
            on: minterAdmin.address,
            from: minterAddr,
            op: Ops.OP_MINTED,
            ec: [[ecId, maxBtcValue]],
            aborted: false,
        });

        console.log("Item minted gas:", computedGeneric(mintedTx).gasUsed);

        expect(res.transactions).not.toHaveTransaction({
            from: minterAdmin.address,
            op: Ops.OP_REFUND_MINT
        });

        const nftSmc  = await blockchain.getContract(minterAdmin.address);
        expect(nftSmc.balance).toEqual(toNano('1'));

        const nftData = await minterAdmin.getNftData();

        expect(nftData.isInit).toBe(true);
        expect(nftData.collection).toEqualAddress(collection.address);
        expect(nftData.index).toEqual(ecId);
        expect(nftData.content).not.toBeNull();

        const jettonData = await minterAdmin.getJettonData();

        expect(jettonData.supply).toBe(0n);
        expect(jettonData.mintable).toBe(true);
        expect(jettonData.owner).toEqualAddress(deployer.address);
        expect(jettonData.content).toEqualCell(nftData.content!);

        expect(res.transactions).toHaveTransaction({
            on: otherWallet.address,
            from: minterAdmin.address,
            value: (v) => v! > 0n,
            ec: [],
            aborted: false
        });

        smc = await blockchain.getContract(minterAddr);
        expect(smc.ec[ecId]).toBeUndefined();
        smc = await blockchain.getContract(minterAdmin.address);
        expect(smc.ec[ecId]).toEqual(maxBtcValue);

        const configData = await getContractData(configAddr);

        const configCell = configData.beginParse().loadRef();
        configDict = Dictionary.loadDirect(Dictionary.Keys.Int(32), Dictionary.Values.Cell(), configCell);
        ecMinted   = Dictionary.load(Dictionary.Keys.Int(32), Dictionary.Values.BigVarUint(5), configDict.get(7)!);

        // Successfully minted new EC
        expect(ecMinted.get(ecId)).toEqual(maxBtcValue);

        blockchain.setConfig(configCell);

        adminMinted = blockchain.snapshot();
    });
    it('same item should not be mintable twice', async () => {

        let countBefore = (await collection.getCollectionDataExtended()).itemCount;
        expect(countBefore).toBeGreaterThan(0);

        let res = await collection.sendNewItem(deployer.getSender(), {
            owner: deployer.address,
            maxSupply: maxBtcValue,
            refund: otherWallet.address,
            index: ecId,
            content: {
                type: 'onchain',
                data: {
                    name: "tgBTC",
                    symbol: "tgBTC",
                    decimals: "9" // Oops
                }
            }
        });

        expect(res.transactions).not.toHaveTransaction({
            on: minterAddr,
            from: minterAdmin.address,
            op: Ops.OP_MINT
        });
        expect(res.transactions).toHaveTransaction({
            from: minterAdmin.address,
            op: Ops.OP_REFUND_MINT,
            body: (b) => {
                const ds = b!.beginParse().skip(64 + 32);
                return ds.loadUint(32) == ecId && ds.loadUint(10) == MintError.ALREADY_INITED
            },
        });

        const countAfter = (await collection.getCollectionDataExtended()).itemCount;
        expect(countAfter).toEqual(countBefore);
    });

    it('not collection owner should not be able to update content', async () => {
        const contentBefore =  (await minterAdmin.getJettonData()).content;

        let content = nftContentToCell({
            type: 'onchain',
            data: {
                name: "tgBTC",
                symbol: "tgBTC",
                decimals: "8", // Updating to 8
            }
        });
        expect(contentBefore).not.toEqualCell(content);

        let res = await collection.sendUpdateContent(otherWallet.getSender(), ecId, content, deployer.address);

        expect(res.transactions).not.toHaveTransaction({
            on: minterAdmin.address,
            from: collection.address,
            op: Ops.OP_UPDATE_CONTENT,
            outMessagesCount: 1,
            aborted: false
        });
        expect(res.transactions).toHaveTransaction({
            on: collection.address,
            from: otherWallet.address,
            op: Ops.OP_UPDATE_CONTENT,
            aborted: true,
            exitCode: MintError.collection.NOT_COLLECTION_OWNER
        });

        expect((await minterAdmin.getJettonData()).content).toEqualCell(contentBefore);
    });

    it('item should not accept content update from not collection address', async () => {
        let content = nftContentToCell({
            type: 'onchain',
            data: {
                name: "tgBTC",
                symbol: "tgBTC",
                decimals: "8", // Updating to 8
            }
        });

        let res= await otherWallet.send({
            to: minterAdmin.address,
            value: toNano('1'),
            body: beginCell().storeUint(Ops.OP_UPDATE_CONTENT, 32)
                    .storeUint(0, 64)
                    .storeUint(ecId, 32) // index
                    .storeRef(content)
                  .endCell()
        });

        expect(res.transactions).toHaveTransaction({
            on: minterAdmin.address,
            from: otherWallet.address,
            op: Ops.OP_UPDATE_CONTENT,
            aborted: true
        });
    });

    it('collection owner should be able to update content', async () => {
        let content = nftContentToCell({
            type: 'onchain',
            data: {
                name: "tgBTC",
                symbol: "tgBTC",
                decimals: "8", // Updating to 8
            }
        });

        let res = await collection.sendUpdateContent(deployer.getSender(), ecId, content, deployer.address);

        expect(res.transactions).toHaveTransaction({
            on: minterAdmin.address,
            from: collection.address,
            op: Ops.OP_UPDATE_CONTENT,
            outMessagesCount: 1,
            aborted: false
        });
        expect(res.transactions).toHaveTransaction({
            on: deployer.address,
            from: minterAdmin.address,
            op: Ops.OP_EXCESS
        });

        expect((await minterAdmin.getJettonData()).content).toEqualCell(content);
    });

    it('minter owner should be able to mint ec', async () => {

        const supplyBefore = (await minterAdmin.getJettonData()).supply;

        let mintAmount = BigInt(getRandomInt(1, 100)) * BigInt(10 ** 8);
        let randomPayload = beginCell().storeUint(getRandomInt(1, 100000), 32).endCell();
        let res = await minterAdmin.sendTransfer(deployer.getSender(), toNano('0.05'), mintAmount, otherWallet.address, deployer.address, randomPayload, toNano('0.01'));
        // console.log(res.transactions[1].blockchainLogs);

        const mintTx = findTransactionRequired(res.transactions, {
            on: minterAdmin.address,
            from: deployer.address,
            op: Ops.OP_TRANSFER_EC,
            body: (b) => {
                return b!.beginParse().preloadRef().equals(randomPayload);
            },
            aborted: false
        });

        const mintGas = computedGeneric(mintTx).gasUsed;

        console.log("Mint gas:", mintGas);

        expect(res.transactions).toHaveTransaction({
            on: otherWallet.address,
            from: minterAdmin.address,
            op: Ops.OP_OUT_EC,
            value: toNano('0.01'),
            ec: [[ecId, mintAmount]],
        });

        const jettonData = await minterAdmin.getJettonData();
        expect(jettonData.supply).toEqual(mintAmount);

        const supplyAfter = (await minterAdmin.getJettonData()).supply;
        expect(supplyAfter).toEqual(supplyBefore + mintAmount);

        coinsMinted = blockchain.snapshot();
    });
    it('mint with no refund should carry incomming value to receiver', async () => {
        const supplyBefore = (await minterAdmin.getJettonData()).supply;

        let mintAmount = BigInt(getRandomInt(1, 100)) * BigInt(10 ** 8);
        let randomPayload = beginCell().storeUint(getRandomInt(1, 100000), 32).endCell();
        let res = await minterAdmin.sendTransfer(deployer.getSender(), toNano('1'), mintAmount, otherWallet.address, null, randomPayload, toNano('0.01'));

        expect(res.transactions).toHaveTransaction({
            on: otherWallet.address,
            from: minterAdmin.address,
            op: Ops.OP_OUT_EC,
            value: v => v! > toNano('0.01'),
            ec: [[ecId, mintAmount]],
        });

        const supplyAfter = (await minterAdmin.getJettonData()).supply;
        expect(supplyAfter).toEqual(supplyBefore + mintAmount);
    });
    it('not owner should not be able to mint ec', async () => {
        const supplyBefore = (await minterAdmin.getJettonData()).supply;

        let mintAmount = BigInt(getRandomInt(1, 100)) * BigInt(10 ** 8);
        let randomPayload = beginCell().storeUint(getRandomInt(1, 100000), 32).endCell();
        let res = await minterAdmin.sendTransfer(otherWallet.getSender(), toNano('0.05'), mintAmount, otherWallet.address, deployer.address, randomPayload, 1n);

        expect(res.transactions).not.toHaveTransaction({
            from: minterAdmin.address,
            op: Ops.OP_OUT_EC
        });

        const supplyAfter = (await minterAdmin.getJettonData()).supply;
        expect(supplyAfter).toEqual(supplyBefore);
    });

    it('minter owner should be able to mint EC using jetton minter interface', async () => {
        const supplyBefore = (await minterAdmin.getJettonData()).supply;
        let mintAmount = BigInt(getRandomInt(1, 100)) * BigInt(10 ** 8);
        // Minter is from basecoin repo, trust me
        let jettonMinter = blockchain.openContract(JettonMinter.createFromAddress(minterAdmin.address));

        let res = await jettonMinter.sendMint(deployer.getSender(), otherWallet.address, mintAmount, null, deployer.address, null, toNano('0.05'), toNano('1'));

        // console.log(res.transactions[1].vmLogs);

        let mintTx = findTransactionRequired(res.transactions, {
            on: minterAdmin.address,
            from: deployer.address,
            op: Ops.OP_MINT_JETTON,
            aborted: false
        });

        const mintGas = computedGeneric(mintTx).gasUsed;
        console.log("Jetton mint gas:", mintGas);

        expect(res.transactions).toHaveTransaction({
            on: otherWallet.address,
            from: minterAdmin.address,
            ec: [[ecId, mintAmount]],
            value: toNano('0.05'),
        });

        const supplyAfter = (await minterAdmin.getJettonData()).supply;
        expect(supplyAfter).toEqual(supplyBefore + mintAmount);
    });

    it('minter should be able to burn EC', async () => {
        const dataBefore  = await minterAdmin.getJettonData();
        let randomPayload = beginCell().storeUint(getRandomInt(1, 100000), 32).endCell();
        let forwardTon    = BigInt(getRandomInt(1, 5)) * toNano('0.001');
        let burnAmount    = BigInt(getRandomInt(1, 5)) * ((await getEcBalance(otherWallet.address, ecId)) / 10n);
        let res = await minterAdmin.sendBurn(otherWallet.getSender(), {[ecId]: burnAmount}, forwardTon, otherWallet.address, randomPayload);

        // console.log(res.transactions[1].vmLogs);
        let burnTx = findTransactionRequired(res.transactions, {
            on: minterAdmin.address,
            from: otherWallet.address,
            ec: [[ecId, burnAmount]],
            aborted: false
        });

        const burnGas = computedGeneric(burnTx).gasUsed;
        console.log("Burn gas:", burnGas);

        expect(res.transactions).toHaveTransaction({
            on: deployer.address,
            from: minterAdmin.address,
            ec: [],
            op: Ops.OP_BURN_NOTIFICATION,
            value: forwardTon,
            body: (b) => {
                let ds = b!.beginParse().skip(32 + 64);
                return ds.loadVarUintBig(5) == burnAmount &&
                       ds.loadAddress().equals(otherWallet.address) &&
                       ds.loadAddress().equals(otherWallet.address) &&
                       ds.loadRef().equals(randomPayload);
            }
        });

        const dataAfter = await minterAdmin.getJettonData();
        expect(dataAfter.supply).toEqual(dataBefore.supply - burnAmount);
    });

    it('minter should not accept multiple EC to burn', async () => {
        const smc = await blockchain.getContract(otherWallet.address);
        smc.ec = {...smc.ec, 456: 100n};

        let res = await minterAdmin.sendBurn(otherWallet.getSender(), {[ecId]: 1n, 456: 1n}, toNano('0.001'), otherWallet.address);

        expect(res.transactions).toHaveTransaction({
            on: minterAdmin.address,
            from: otherWallet.address,
            op: Ops.OP_BURN_EC,
            aborted: true,
            exitCode: MintError.INVALID_EC,
        });
        expect(res.transactions).toHaveTransaction({
            on: otherWallet.address,
            inMessageBounced: true,
            ec: [[ecId, 1n], [456, 1n]]
        });
    });

    it('minter should not be able to update content after mint', async () => {
        const stateBefore = blockchain.snapshot();

        const adminData = await  minterAdmin.getJettonData();
        expect(adminData.supply).toBeGreaterThan(0n);
        const contentBefore = adminData.content!;

        let newContent = nftContentToCell({
            type: 'onchain',
            data: {
                name: "tgBTC",
                symbol: "tgBTC",
                decimals: "6",
            }
        });

        expect(contentBefore).not.toEqualCell(newContent);

        let res = await collection.sendUpdateContent(deployer.getSender(), ecId, newContent, deployer.address);

        expect(res.transactions).toHaveTransaction({
            on: deployer.address,
            from: minterAdmin.address,
            op: Ops.OP_FAILED,
            body: (b) => {
                const ds = b!.beginParse().skip(32 + 64);
                return ds.loadUint(10) == MintError.ALREADY_MINTED
            }
        });


        const contentAfter = (await minterAdmin.getJettonData()).content;
        expect(contentAfter).toEqualCell(contentBefore);

        const smc = await blockchain.getContract(otherWallet.address);

        await minterAdmin.sendBurn(otherWallet.getSender(), {[ecId]: smc.ec[ecId]}, 0n)

        let dataAfter = await minterAdmin.getJettonData();
        expect(dataAfter.supply).toBe(0n);

        // Now it should work again
        res = await collection.sendUpdateContent(deployer.getSender(), ecId, newContent, deployer.address);
        expect(res.transactions).toHaveTransaction({
            on: minterAdmin.address,
            from: collection.address,
            op: Ops.OP_UPDATE_CONTENT,
            aborted: false
        });


        dataAfter = await minterAdmin.getJettonData();
        expect(dataAfter.content).toEqualCell(newContent);

        await blockchain.loadFrom(stateBefore);
    });

    it('collection owner should not be able to reset already initialized item', async () => {
        const statusBefore = (await minterAdmin.getDataExtended()).status;
        expect(statusBefore).toBe(2); // Fully initialized

        const res = await collection.sendResetItem(deployer.getSender(), ecId, otherWallet.address);

        expect(res.transactions).toHaveTransaction({
            on: minterAdmin.address,
            from: collection.address,
            op: Ops.OP_RESET,
            aborted: false
        });

        expect(res.transactions).toHaveTransaction({
            on: otherWallet.address,
            from: minterAdmin.address,
            op: Ops.OP_FAILED,
            body: (b) => {
                const ds = b!.beginParse().skip(32 + 64);
                return ds.loadUint(10) == MintError.ALREADY_INITED
            }
        });

        const statusAfter = (await minterAdmin.getDataExtended()).status;
        expect(statusAfter).toEqual(statusBefore);
    });

    it('collection owner should be able to reset item state in case of mint failure', async () => {
        mintIdx = getRandomInt(5, 10);

        const nftItem = await getNftItem(mintIdx);

        const testMsg = MinterNFTCollection.newItemMessage({
            owner: otherWallet.address,
            maxSupply: toNano('100'),
            refund: otherWallet.address,
            index: mintIdx,
            content: {
                type: 'onchain',
                data: {
                    name: "tgBTC",
                    symbol: "tgBTC",
                    decimals: "9" // Oops
                }
            }
        }, toNano('3'));

        let res = await blockchain.sendMessageIter(internal({
            from: deployer.address,
            to: collection.address,
            value: toNano('10'),
            body: testMsg
        }));

        // Let's stop on item->minter first step
        await executeTill(res, {
            on: minterAddr,
            from: nftItem.address,
            op: Ops.OP_MINT,
        });

        mintInProgress = blockchain.snapshot();
        // And pretend that message never came back, so admin tries to reset it
        const resetMsg = MinterNFTCollection.resetItemMessage(mintIdx, otherWallet.address);

        const statusBefore = (await nftItem.getDataExtended()).status;

        expect(statusBefore).toBe(1); // Awaiting init

        let resetRes = await blockchain.sendMessageIter(internal({
            from: deployer.address,
            to: collection.address,
            body: resetMsg,
            value: toNano('1')
        }));

        await executeTill(resetRes, {
            on: nftItem.address,
            from: collection.address,
            op: Ops.OP_RESET
        });

        const statusAfter = (await nftItem.getDataExtended()).status;
        expect(statusAfter).toBe(0);
    });

    it('collection should not allow not owner to reset items', async () => {
        await blockchain.loadFrom(mintInProgress);

        const res = await collection.sendResetItem(otherWallet.getSender(), ecId, otherWallet.address);
        expect(res.transactions).toHaveTransaction({
            on: collection.address,
            from: otherWallet.address,
            op: Ops.OP_RESET,
            aborted: true,
            exitCode: MintError.collection.NOT_COLLECTION_OWNER
        });
    });

    it('item should not accept reset op other than from collection', async () => {
        await blockchain.loadFrom(mintInProgress);

        const res = await deployer.send({
            to: minterAdmin.address,
            value: toNano('1'),
            body: beginCell()
                    .storeUint(Ops.OP_RESET, 32)
                    .storeUint(0, 64)
                    .storeUint(ecId, 32) // Item index
                    .storeAddress(deployer.address)
                  .endCell()
        });

        expect(res.transactions).toHaveTransaction({
            on: minterAdmin.address,
            from: deployer.address,
            op: Ops.OP_RESET,
            aborted: true,
            exitCode: MintError.INVALID_SENDER
        });
    });

    it('in case minted message doesn\'t match requested, item should refund everything to collection', async () => {

        await blockchain.loadFrom(mintInProgress);
        // Ugh
        const nftItem = await getNftItem(mintIdx);

        const maxSupply = (await nftItem.getDataExtended()).maxSupply;

        const templateMsg = {
            to: nftItem.address,
            from: minterAddr,
            value: toNano('1'),
        };

        let defaultEc = [[mintIdx, maxSupply]];

        const refPayload = beginCell().storeUint(1, 1).storeAddress(otherWallet.address).endCell();

        const badIdx = [{
            ...templateMsg,
            ec: defaultEc,
            body: beginCell()
                    .storeUint(Ops.OP_MINTED, 32)
                    .storeUint(0, 64)
                    .storeUint(mintIdx - 1, 32)
                    .storeVarUint(maxSupply, 5)
                    .storeMaybeRef(refPayload)
                  .endCell()
        }, MintError.INVALID_INDEX];

        const badSupply = [{
            ...templateMsg,
            ec: defaultEc,
            body: beginCell()
                    .storeUint(Ops.OP_MINTED, 32)
                    .storeUint(0, 64)
                    .storeUint(mintIdx, 32)
                    .storeVarUint(maxSupply - 1n, 5)
                    .storeMaybeRef(refPayload)
                  .endCell()
        }, MintError.INVALID_SUPPLY];

        const notEnoughEC = [{
            ...templateMsg,
            ec: [[mintIdx, maxSupply - 1n]],
            body: beginCell()
                    .storeUint(Ops.OP_MINTED, 32)
                    .storeUint(0, 64)
                    .storeUint(mintIdx, 32)
                    .storeVarUint(maxSupply, 5)
                    .storeMaybeRef(refPayload)
                  .endCell()
        }, MintError.NOT_ENOUGH_EC];

        const differentEc = [{
            ...templateMsg,
            ec: [[ecId, maxSupply]],
            body: beginCell()
                    .storeUint(Ops.OP_MINTED, 32)
                    .storeUint(0, 64)
                    .storeUint(mintIdx, 32)
                    .storeVarUint(maxSupply, 5)
                    .storeMaybeRef(refPayload)
                  .endCell()
        }, MintError.NOT_ENOUGH_EC];

        const malformedPayload = [{
            ...templateMsg,
            ec: [[mintIdx, maxSupply]],
            body: beginCell()
                    .storeUint(Ops.OP_MINTED, 32)
                    .storeUint(0, 64)
                    .storeUint(mintIdx, 32)
                    .storeVarUint(maxSupply, 5)
                    .storeUint(1,1)
                  .endCell()
        }, 9];


        for (let testCase of [badIdx, badSupply, differentEc, notEnoughEC, malformedPayload]) {
            await blockchain.loadFrom(mintInProgress);
            let collectionBefore = await collection.getCollectionDataExtended();
            const conditions = testCase[0] as any; //as Parameters<typeof internal>[0];
            let res = await blockchain.sendMessage(internal(conditions));

            expect(res.transactions).toHaveTransaction({
                on: collection.address,
                from: nftItem.address,
                ec: conditions.ec,
                op: Ops.OP_REFUND_MINT,
                body: (b) => {
                    const ds = b!.beginParse().skip(64 + 32);
                    return ds.loadUint(32) == mintIdx && ds.loadUint(10) == testCase[1];
                },
                aborted: false
            });
            // Collection should proxy value to collection owner
            expect(res.transactions).toHaveTransaction({
                on: deployer.address,
                from: collection.address,
                ec: conditions.ec,
                op: Ops.OP_REFUND_MINT,
                inMessageBounceable: false
            });

            let collectionAfter = await collection.getCollectionDataExtended();
            expect(collectionAfter.itemCount).toBeGreaterThan(0);
            // Collection should roll back the item count
            expect(collectionAfter.itemCount).toEqual(collectionBefore.itemCount - 1);
        }
    });
    it('anyone should be able to rebalance minter item', async () => {
        /*
         * extra blance lookup has to cost constant gas,
         * that's why it is stored in the contract data.
         *
         * Rebalance  allows to make balance in data to equal
         * actual balance from AccountState
         * supply = maxSupply - balance
         */

         // Let's imagine someone sent EC to the contract with no TONs

         let smc = await blockchain.getContract(minterAdmin.address);
         const supplyBefore = (await minterAdmin.getJettonData()).supply;

         const balanceBefore = smc.ec[ecId];

         const burnMsg = MinterNFTAdmin.burnMessage(0n);

         await otherWallet.send({
             to: minterAdmin.address,
             body: burnMsg,
             extracurrency: {[ecId]: 1n},
             value: 0n,
             sendMode: SendMode.PAY_GAS_SEPARATELY
         });


         let supplyAfter = (await minterAdmin.getJettonData()).supply;
         // For now those will equal, because there was no gas to update balance
         expect(supplyAfter).toEqual(supplyBefore);

         let walletSmc = await blockchain.getContract(otherWallet.address);

         const rebalaceMsg = MinterNFTAdmin.rebalanceMessage(0);
         // Let's be tricky, and send rebalance message
         // with some incomming EC value
         // It should not impact balance calculations

         const additionalEc = walletSmc.ec[ecId] / 10n;
         expect(additionalEc).toBeGreaterThan(0n);

         const res = await otherWallet.send({
             to: minterAdmin.address,
             body: rebalaceMsg,
             extracurrency: {[ecId]: additionalEc},
             value: toNano('1'),
             sendMode: SendMode.PAY_GAS_SEPARATELY
         });

         expect(res.transactions).toHaveTransaction({
             on: minterAdmin.address,
             from: otherWallet.address,
             op: Ops.OP_REBALANCE,
             aborted: false
         });
         expect(res.transactions).toHaveTransaction({
             on: otherWallet.address,
             from: minterAdmin.address,
             op: Ops.OP_EXCESS
         });

         supplyAfter = (await minterAdmin.getJettonData()).supply;
         // Balance on the account increased by 1, so circulating supply decreased by 1
         expect(supplyAfter).toEqual(supplyBefore - 1n);
    });
    it('item owner should be able to withdraw excess tons and EC', async () => {
        const prevState = blockchain.snapshot();

        const smc = await blockchain.getContract(minterAdmin.address);
        const amount456  = BigInt(getRandomInt(1, 1000));
        const amount789  = BigInt(getRandomInt(1, 1000));

        smc.ec = {...smc.ec, 456: amount456, 789: amount789};
        smc.balance = toNano('1000');

        const withExcess = blockchain.snapshot();

        const res = await minterAdmin.sendWithdrawExcessEC(deployer.getSender(), deployer.address, {withdrawSpecific: false, fromBalance: toNano('100')});
        expect(res.transactions).toHaveTransaction({
            on: deployer.address,
            from: minterAdmin.address,
            op: Ops.OP_EXCESS,
            value: (v) => v! >= toNano('100'),
            ec: [
                    [456, amount456],
                    [789, amount789],
            ]
        });
        await blockchain.loadFrom(withExcess);

        const amountMap: { [k: number] : bigint } = {
            456: amount456,
            789: amount789
        }

        for(let wId of [456, 789]) {
            const res = await minterAdmin.sendWithdrawExcessEC(deployer.getSender(), deployer.address, {withdrawSpecific: true, curId: wId, fromBalance: toNano('1')});

            expect(res.transactions).toHaveTransaction({
                on: deployer.address,
                from: minterAdmin.address,
                op: Ops.OP_EXCESS,
                value: (v) =>  v! >= toNano('1'),
                ec: [[wId, amountMap[wId]]]
            });
        }

        const idxEc = await minterAdmin.sendWithdrawExcessEC(deployer.getSender(), deployer.address, {withdrawSpecific: true, curId: ecId, fromBalance: toNano('1')});
        expect(idxEc.transactions).toHaveTransaction({
            on: minterAdmin.address,
            from: deployer.address,
            op: Ops.OP_WITHDRAW_EXTRA,
            aborted: true,
            exitCode: MintError.INVALID_EC
        });
        await blockchain.loadFrom(prevState);
    });
    it('collection owner should be able to withdraw excess tons and EC', async () => {
        const prevState = blockchain.snapshot();

        const smc = await blockchain.getContract(collection.address);
        const amount456  = BigInt(getRandomInt(1, 1000));
        const amount789  = BigInt(getRandomInt(1, 1000));

        smc.ec = {...smc.ec, 456: amount456, 789: amount789};
        smc.balance = toNano('1000');

        const withExcess = blockchain.snapshot();

        const res = await collection.sendWithdrawExcessEC(deployer.getSender(), deployer.address, {withdrawSpecific: false, fromBalance: toNano('100')});
        expect(res.transactions).toHaveTransaction({
            on: deployer.address,
            from: collection.address,
            op: Ops.OP_EXCESS,
            value: (v) => v! >= toNano('100'),
            ec: [
                    [456, amount456],
                    [789, amount789],
            ]
        });
        await blockchain.loadFrom(withExcess);

        const amountMap: { [k: number] : bigint } = {
            456: amount456,
            789: amount789
        }

        for(let wId of [456, 789]) {
            const res = await collection.sendWithdrawExcessEC(deployer.getSender(), deployer.address, {withdrawSpecific: true, curId: wId, fromBalance: toNano('1')});

            expect(res.transactions).toHaveTransaction({
                on: deployer.address,
                from: collection.address,
                op: Ops.OP_EXCESS,
                value: (v) =>  v! >= toNano('1'),
                ec: [[wId, amountMap[wId]]]
            });
        }
        await blockchain.loadFrom(prevState);
    });
    it('non-owner should not be able to withdraw excess tons and EC', async () => {
        const prevState = blockchain.snapshot();

        const smc = await blockchain.getContract(minterAdmin.address);
        const amount456  = BigInt(getRandomInt(1, 1000));
        const amount789  = BigInt(getRandomInt(1, 1000));

        smc.ec = {...smc.ec, 456: amount456, 789: amount789};
        smc.balance = toNano('1000');

        const withExcess = blockchain.snapshot();

        const withdrawAll = minterAdmin.sendWithdrawExcessEC(otherWallet.getSender(), deployer.address, {withdrawSpecific: false, fromBalance: toNano('100')});

        let withdrawSpecific = async (id: number) => {
            return await minterAdmin.sendWithdrawExcessEC(otherWallet.getSender(), deployer.address, {withdrawSpecific: true, curId: id, fromBalance: toNano('100')});
        }

        const results = [await withdrawAll, await withdrawSpecific(456), await withdrawSpecific(789)];

        for(let res of results) {
            expect(res.transactions).toHaveTransaction({
                on: minterAdmin.address,
                from: otherWallet.address,
                aborted: true,
                outMessagesCount: 1
            });
        }

        await blockchain.loadFrom(prevState);
    });
    it('collection should retain functionality in case of malformed config', async () => {
        await blockchain.loadFrom(coinsMinted);
        const stateBefore = await collection.getCollectionDataExtended();

        let configDict = Dictionary.loadDirect(Dictionary.Keys.Int(32), Dictionary.Values.Cell(), blockchain.config);


        let authConfig = Dictionary.loadDirect(Dictionary.Keys.Uint(8), authorizationRecordValue(), configDict.get(authConfigId)!);
        // Item relies on config to map version to collections
        authConfig.set(COLLECTION_VERSION + 1, authConfig.get(COLLECTION_VERSION)!);
        authConfig.delete(COLLECTION_VERSION);
        configDict.set(authConfigId, beginCell().storeDictDirect(authConfig).endCell());
        blockchain.setConfig(beginCell().storeDictDirect(configDict).endCell());

        const stateAfter = await collection.getCollectionDataExtended();

        // Should map to the same address
        const testNft = await getNftItem(ecId);
        expect(testNft.address).toEqualAddress(minterAdmin.address);

        // But should not allow to mint new stuff

        let res = await collection.sendNewItem(deployer.getSender(), {
            owner: otherWallet.address,
            maxSupply: maxBtcValue,
            refund: otherWallet.address,
            index: ecId,
            content: {
                type: 'onchain',
                data: {
                    name: "wBTC",
                    symbol: "wBTC",
                    decimals: "9" // Oops
                }
            }
        });

        expect(res.transactions).toHaveTransaction({
            on: collection.address,
            op: Ops.OP_NEW_ITEM,
            aborted: true,
            exitCode: MintError.collection.COLLECTION_MISCONFIG + MintError.collection.COLLECTION_NOT_IN_CONFIG
        });

        expect(stateAfter.itemCode).toEqualCell(stateBefore.itemCode);
        expect(stateAfter.itemCount).toEqual(stateBefore.itemCount);
    });

    describe('Bounce', () => {
        beforeEach(async () => await blockchain.loadFrom(mintInProgress));

        it('item should handle OP_MINT bounce', async() => {

            const nftItem = await getNftItem(mintIdx);

            const itemBefore = await nftItem.getDataExtended();
            const itemCountBefore = (await collection.getCollectionDataExtended()).itemCount;

            expect(itemBefore.status).toBe(1);
            let ecValue = BigInt(getRandomInt(1, 1000)) * toNano('0.01');

            const res = await blockchain.sendMessageIter(internal({
                from: minterAddr,
                to: nftItem.address,
                value: toNano('1'),
                ec: [[ecId, ecValue]],
                body: beginCell().storeUint(BigInt((2 ** 32) - 1), 32)
                                 .storeUint(Ops.OP_MINT, 32)
                      .endCell(),
                bounce: false,
                bounced: true
            }));

            await executeTill(res, {
                on: collection.address,
                from: nftItem.address,
                ec: [[ecId, ecValue]],
                op: Ops.OP_REFUND_MINT
            });

            const itemAfter = await nftItem.getDataExtended();
            expect(itemAfter.status).toBe(0);
            const itemCountAfter = (await collection.getCollectionDataExtended()).itemCount;
            expect(itemCountAfter).toBeGreaterThan(0);
            expect(itemCountAfter).toEqual(itemCountBefore - 1);
        });

        it('collection should handle mint bounce from item', async () => {
            const nftItem = await getNftItem(mintIdx);
            const itemCountBefore = (await collection.getCollectionDataExtended()).itemCount;

            const res = await blockchain.sendMessageIter(internal({
                from: nftItem.address,
                to: collection.address,
                value: toNano('1'),
                body: beginCell().storeUint(BigInt((2 ** 32) - 1), 32)
                                 .storeUint(Ops.OP_NEW_ITEM, 32)
                      .endCell(),
                bounce: false,
                bounced: true
            }));

            await executeTill(res, {
                on: deployer.address,
                from: collection.address,
                op: Ops.OP_NEW_ITEM
            });

            const itemCountAfter = (await collection.getCollectionDataExtended()).itemCount;
            expect(itemCountAfter).toBeGreaterThan(0);
            expect(itemCountAfter).toEqual(itemCountBefore - 1);
        });
    });
});
