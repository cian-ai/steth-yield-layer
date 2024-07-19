import { CURRENT_RPC } from "../../../hardhat.config";
import { ethers } from "hardhat";
import { BigNumberish } from "ethers";
import { toBigNumber, sleep } from "./utils";

export async function mintToken(
    receiver: string,
    underlying: string,
    amount: number,
    decimals: number,
    rpc?: string,
    slot?: FindSlot.SlotResult
) {
    if (decimals == 0) console.log(underlying, "decimals error");
    let amountx: string = toBigNumber(amount, decimals).toHexString();
    // Try loading slot from json.
    // If not found, try auto find.
    if (slot == undefined) {
        slot = await FindSlot.autoFindBalanceSlot(underlying, rpc);
    }
    await Minter.setBalanceOf(amountx, receiver, underlying, slot);
}

export module FindSlot {
    // The result of the token balance slot.
    export type SlotResult = { slot: string; contract: string };

    const OpSLOAD = "SLOAD";
    const OpSHA3 = "SHA3";

    // Can be any address.
    const addressTest = "0x33d356c89479F97C9d5B3f176B5E2d1AFbA531F7";
    const sender = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

    export async function autoFindBalanceSlot(contract: string, rpc?: string): Promise<SlotResult> {
        if (rpc == "" || rpc == undefined) rpc = CURRENT_RPC;
        const provider = new ethers.providers.JsonRpcProvider(rpc);

        await provider.send("hardhat_impersonateAccount", [sender]);
        await provider.send("hardhat_setBalance", [sender, "0x10000000000000000"]);

        let erc20 = new ethers.Contract("", require("../abi/ERC20.json"), provider);
        let payload = erc20.interface.encodeFunctionData("balanceOf", [addressTest]);
        let tx = await provider.send("eth_sendTransaction", [
            { from: sender, to: contract, data: payload, gas: "0x50000" },
        ]);
        await sleep(1);
        let trace = await provider.send("debug_traceTransaction", [tx, { disableMemory: false, enableMemory: true }]);
        // Find SLOAD op from trace.
        return findStorageLoad(trace);
    }

    function findStorageLoad(input: any): SlotResult {
        let logs = input.structLogs;
        for (let i = 0; i < logs.length; i++) {
            if (logs[i].op !== OpSLOAD) continue;
            // Find SHA3 op
            for (let j = 1; j < 15; j++) {
                if (logs[i - j].op !== OpSHA3) continue;
                // Access Memory
                // Get stack status.
                let stack = logs[i - j].stack;
                let stackTop = parseInt(stack[stack.length - 1]);
                let begin_location = stackTop / 32;
                let mem = logs[i - j].memory;
                let top: string = mem[begin_location];
                let top2: string = mem[begin_location + 1];
                if (top.slice(24) == trimAddress(addressTest)) {
                    return { slot: top2, contract: "solidity" };
                } else if (top2.slice(24) == trimAddress(addressTest)) {
                    return { slot: top, contract: "vyper" };
                }
            }
        }
        return { slot: "0", contract: "solidity" };
    }

    function trimAddress(address: string): string {
        return address.replace(/^0x/, "").toLocaleLowerCase();
    }
}

export module Minter {
    export function padToUint256(value: string): string {
        return ethers.utils.hexZeroPad(value, 32);
    }

    export async function storageModifier(address: string, slot: BigNumberish, value: BigNumberish) {
        await ethers.provider.send("hardhat_setStorageAt", [
            address,
            slot.toString().replace(/^0x0+/, "") != "" ? slot.toString().replace(/^0x0+/, "0x") : "0x0",
            value,
        ]);
    }

    export async function slotHash(location: BigNumberish, key: BigNumberish): Promise<string> {
        return ethers.utils.keccak256(ethers.utils.solidityPack(["uint256", "uint256"], [location, key]));
    }

    export async function setBalanceOf(
        balanceHex: string,
        address: string,
        contract: string,
        slotInfo: FindSlot.SlotResult
    ) {
        let slot: BigNumberish = slotInfo.slot;
        if (slotInfo.contract == "solidity") {
            slot = await slotHash(ethers.utils.hexZeroPad(address, 32), slotInfo.slot);
        } else {
            slot = await slotHash(slotInfo.slot, ethers.utils.hexZeroPad(address, 32));
        }
        await storageModifier(contract, slot, ethers.utils.hexZeroPad(balanceHex, 32));
    }
}
