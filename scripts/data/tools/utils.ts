import { CURRENT_RPC } from "../../../hardhat.config";
import { BigNumber, Contract, Signer } from "ethers";
import { ethers } from "hardhat";
import { setBalance } from "@nomicfoundation/hardhat-network-helpers";

export async function impersonateAccount(address: string): Promise<Signer> {
    const provider = new ethers.providers.JsonRpcProvider(CURRENT_RPC);
    const balance: BigNumber = await ethers.provider.getBalance(address);
    if (balance.lte(toBigNumber(1, 18))) await setETH(address, 100);
    await provider.send("hardhat_impersonateAccount", [address]);
    const signer = provider.getSigner(address);
    return signer;
}

export async function stopImpersonateAccount(address: string) {
    const provider = new ethers.providers.JsonRpcProvider(CURRENT_RPC);
    await provider.send("hardhat_stopImpersonatingAccount", [address]);
}

export async function setETH(address: string, amount: number) {
    await setBalance(address, toBigNumber(amount, 18));
}

export async function printBalance(owner: string, ownerName: string, underlying: string, symbol?: string) {
    if (underlying == "") return;
    const provider = new ethers.providers.JsonRpcProvider(CURRENT_RPC);
    const token: Contract = new ethers.Contract(underlying, require("../abi/IERC20Metadata.json"), provider);
    const decimals: number = fromBigNumber(await token.decimals());
    if (symbol == "" || symbol == undefined) symbol = await token.symbol();
    const balance: number = fromBigNumber(await token.balanceOf(owner), decimals);
    console.log(`${ownerName} ${owner} ${symbol} Balance : ${balance}`);
}

export async function getBalance(owner: string, underlying: string, blockNumber?: number): Promise<BigNumber> {
    const provider = new ethers.providers.JsonRpcProvider(CURRENT_RPC);
    const token: Contract = new ethers.Contract(underlying, require("../abi/IERC20Metadata.json"), provider);
    const balance: BigNumber = await token.balanceOf(owner, { blockTag: blockNumber });
    return balance;
}

export async function printGas(txResult: any) {
    console.log("gasPrice : ", txResult.gasPrice);
    console.log("gasLimit : ", txResult.gasLimit);
    console.log("gasUsed  : ", ethers.utils.formatEther(txResult.gasPrice.mul(txResult.gasLimit)));
}

export async function printETHBalance(owner: string, name: string) {
    const balance: BigNumber = await ethers.provider.getBalance(owner);
    console.log(`${name} ${owner} ETH Balance : ${ethers.utils.formatUnits(balance, 18)}`);
}

export async function getETHBalance(owner: string): Promise<BigNumber> {
    const balance: BigNumber = await ethers.provider.getBalance(owner);
    return balance;
}

export async function robFromWhale(underlying: string, whale: string, to: string, amount: number) {
    let whaleCodePrev: string = await ethers.provider.getCode(whale);

    let token: Contract;
    // Get the token with impersonate.
    {
        await setETH(whale, 100);
        await ethers.provider.send("hardhat_setCode", [whale, "0x"]);
        const signer = await impersonateAccount(whale);
        token = new ethers.Contract(underlying, require("../abi/IERC20Metadata.json"), signer);
    }

    // Decide the amount and transfer.
    {
        let decimals = await token.decimals();
        let amountx: BigNumber = toBigNumber(amount, decimals);
        let balance: BigNumber = await token.balanceOf(whale);
        let robAmount: BigNumber = amount == 0 ? balance : amountx.gte(balance) ? balance : amountx;
        await token.transfer(to, robAmount);
    }

    await stopImpersonateAccount(whale);
    await ethers.provider.send("hardhat_setCode", [whale, whaleCodePrev]);
}

export async function sleep(seconds: number) {
    return new Promise((resolve) => setTimeout(resolve, seconds * 1000));
}

export function toBigNumber(number: number, deciamls: number = 0): BigNumber {
    // let base: number = deciamls >= 18 ? 18 : deciamls >= 8 ? 8 : deciamls >= 6 ? 6 : 0;
    const base: number = deciamls >= 8 ? 8 : deciamls >= 6 ? 6 : 0;
    return ethers.utils.parseUnits(Math.floor(number * 10 ** base).toString(), deciamls - base);
}

export function fromBigNumber(number: BigNumber, deciamls: number = 0): number {
    if (number == undefined) return 0;
    return Number(ethers.utils.formatUnits(number, deciamls));
}

export async function getTxTimestamp(tx: any) {
    let provider = new ethers.providers.JsonRpcProvider(CURRENT_RPC);
    let transactionReceipt = await provider.getTransactionReceipt(tx.hash);
    let block = await provider.getBlock(transactionReceipt.blockHash);
    if (block == null) return 0;
    return block.timestamp;
}
