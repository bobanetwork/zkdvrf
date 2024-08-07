import hre, {artifacts, ethers} from "hardhat";
import {Contract, ContractFactory, providers, utils, Wallet} from "ethers";
import {readJsonFromFile} from "../utils";

const config = readJsonFromFile("demo-config.json")
const rpcUrl = config.rpcUrl
const zkdvrfAddress = config.zkdvrfAddress
const adminKey = config.lotteryAdminKey

async function main() {
    const netprovider = new providers.JsonRpcProvider(rpcUrl)
    const deployerWallet = new Wallet(adminKey, netprovider)

    const Lottery = await ethers.getContractFactory('Lottery')
    const lottery = await Lottery.connect(deployerWallet).deploy(zkdvrfAddress)
    await lottery.deployed()

    console.log("Lottery contract deployed at", lottery.address)
}

main().then(() => {
    process.exit(0);
})
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
