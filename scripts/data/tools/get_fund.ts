import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { accounts } from "./constants";
import { toBigNumber } from "./utils";
import { isAnvil } from "./anvil";
import { CURRENT_RPC } from "../../../hardhat.config";

async function ethInit() {
    const isForkAnvil = await isAnvil();
    const amount = 1000000;
    const amountx = toBigNumber(amount, 18);
    if (isForkAnvil) {
        const provider = new ethers.providers.JsonRpcProvider(CURRENT_RPC);
        for (let i = 0; i < accounts.length; i++) {
            await provider.send("hardhat_setBalance", [accounts[i], amountx.toHexString()]);
            console.log(`users ${accounts[i]} ETH balance set as ${amount}.`);
        }
    } else {
        for (let i = 0; i < accounts.length; i++) {
            await setBalance(accounts[i], amountx);
            console.log(`users ${accounts[i]} ETH balance set as ${amount}.`);
        }
    }
}

const main = async (): Promise<any> => {
    console.log("ETH amount init");
    await ethInit();
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
