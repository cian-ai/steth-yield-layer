import { ethers } from "hardhat";
import { CURRENT_RPC } from "../../../hardhat.config";
import { config as dotEnvConfig } from "dotenv";

dotEnvConfig();

export async function isAnvil() {
    const provider = new ethers.providers.JsonRpcProvider(CURRENT_RPC);
    let version: string | undefined;
    try {
        version = (await provider.send("web3_clientVersion", [])) as string;
        console.log("version = ", version);
        return version.toLowerCase().startsWith("anvil");
    } catch (e) {
        return false;
    }
}

export async function isTestEnv() {
    const provider = new ethers.providers.JsonRpcProvider(CURRENT_RPC);
    let version: string | undefined;
    try {
        version = (await provider.send("web3_clientVersion", [])) as string;
        console.log("version = ", version);
        return version.toLowerCase().startsWith("anvil") || version.toLowerCase().startsWith("hardhat");
    } catch (e) {
        return false;
    }
}
