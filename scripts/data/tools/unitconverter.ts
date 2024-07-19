import { BigNumber } from "ethers";
import { ethers } from "hardhat";

export const oneEther: BigNumber = ethers.utils.parseEther("1.0");
export const oneUsd: BigNumber = ethers.utils.parseUnits("1.0", 6);
export const oneBtc: BigNumber = ethers.utils.parseUnits("1.0", 8);
export const fullAmount = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
