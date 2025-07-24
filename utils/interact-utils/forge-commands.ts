import { $ } from "zx";
import * as dotenv from 'dotenv';

dotenv.config();
  
const chainId = process.env.CUSTOM_TOOLING_CHAINID;
const rpcURL = process.env.CUSTOM_TOOLING_RPC_URL;

if(!chainId || !rpcURL){
  throw new Error('Running forge-commands needs a working <CUSTOM_TOOLING_CHAINID> and <CUSTOM_TOOLING_RPC_URL> on .env.');
}

export const liquidateTroves = async (index, formattedValues) => {
    await $`forge script script/QuillGovernance/LiquidateTrovesLocal.s.sol ${index} ${formattedValues} \
    --sig 'run(uint256,uint256[])' \
    --chain-id ${chainId} \
    --rpc-url ${rpcURL} \
    --broadcast`;
};

export const shutdownBranch = async (branchIndex) => {
  await $`forge script script/QuillGovernance/ShutdownBranchLocal.s.sol ${branchIndex} \
    --sig 'run(uint256)' \
    --chain-id ${chainId} \
    --rpc-url ${rpcURL} \
    --broadcast`;
};

export const getStateSnapshotLocal = async () => {
    await $`forge script script/QuillGovernance/GetStateSnapshotLocal.s.sol \
    --chain-id ${chainId} \
    --rpc-url ${rpcURL} \
    --broadcast`;
}

export const setPrice = async(collIndex, newWeiValue) => {
  await $`forge script script/QuillGovernance/ChangeCollPriceLocal.s.sol ${collIndex} ${newWeiValue} \
    --sig 'run(uint256,uint256)' \
    --chain-id ${chainId} \
    --rpc-url ${rpcURL} \
    --broadcast`;
}

export const redeemCollateralLocal = async(privateKey, amount) => {
  await $`INTERACT_ACTOR_PRIVATEKEY=${privateKey} forge script \
    script/QuillGovernance/RedeemCollateralLocal.s.sol ${amount} \
    --sig 'run(uint256)' \
    --chain-id ${chainId} \
    --rpc-url ${rpcURL} \
    --broadcast`;
}