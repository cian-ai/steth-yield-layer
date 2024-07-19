import { ethers } from "hardhat";
import { Project } from "../utils/deployed";
import { CURRENT_RPC } from "../../hardhat.config";
import { impersonateAccount } from "../data/tools/utils";

const { LedgerSigner } = require("@anders-t/ethers-ledger");
// const Web3 = require("web3");
// const web3 = new Web3(CURRENT_RPC);
const ledger = new LedgerSigner(ethers.provider);
var signer;
var Vault;

async function query() {
    console.log("\n\n\n\ninitialize Strategy");
    console.log(Project);
    // console.log(publicData);
    Vault = await ethers.getContractAt("VaultYieldETH", Project.Vault);
    // signer = await ledger;
    signer = (await ethers.getSigners())[1];
}

async function initializeRedeemOperator() {
    console.log("initializeRedeemOperator");

    const MultiSiger = await impersonateAccount(Project.MultiSig);
    await Vault.connect(MultiSiger).updateRedeemOperator(Project.RedeemOperator);
}

async function addFlashloanWhitelist() {
    console.log("addFlashloanWhitelist");

    const FlashloanHelper = await ethers.getContractAt(
        "IFlashloanHelper",
        "0x49d9409111a6363d82C4371fFa43fAEA660C917B"
    );
    const admin = await impersonateAccount("0x12A59eab07b1Cdd176dad9E4cBbe7Dd973C95d0E");
    await FlashloanHelper.connect(admin).addToWhitelist(Project.StrategyAAVEV3);
    await FlashloanHelper.connect(admin).addToWhitelist(Project.StrategyAAVEV3LIDO);
    await FlashloanHelper.connect(admin).addToWhitelist(Project.StrategyMorphoBlueRSETH);
}

async function removeCap() {
    await ethers.provider.send("hardhat_setStorageAt", [
        // Remove aave deposit celling
        "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
        "0x8ceade8e25499bbf43e93c54022788a929205aeed9322007025beb95ec50b2e3",
        "0x000000000000000000000103e80000000000000249f01194851229fe1d4c1c52",
    ]);
    await ethers.provider.send("hardhat_setStorageAt", [
        // Remove spark debt celling
        "0xC13e21B648A5Ee794902342038FF3aDAB66BE987",
        "0x8ceade8e25499bbf43e93c54022788a929205aeed9322007025beb95ec50b2e3",
        "0x000000000000000000000003e80000075d600000000005dc01122af81c841c20",
    ]);
}

const main = async (): Promise<any> => {
    await query();
    await initializeRedeemOperator();
    await addFlashloanWhitelist();
    await removeCap();
};
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
