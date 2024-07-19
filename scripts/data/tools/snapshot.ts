import { ethers } from "hardhat";

var prevSnapshotId: string;

export async function snapshot() {
    let snapshotId = await ethers.provider.send("evm_snapshot", []);
    prevSnapshotId = snapshotId;
    return prevSnapshotId;
}

export async function revert(snapshotId: string) {
    await ethers.provider.send("evm_revert", [snapshotId]);
}

export async function revertToLast() {
    await ethers.provider.send("evm_revert", [prevSnapshotId]);
}

export function getPrevSnapshotId() {
    return prevSnapshotId;
}
