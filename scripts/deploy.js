const hre = require("hardhat");

async function main() {
    console.log("Deploying");
    const KYC = await hre.ethers.getContractFactory("kyc");
    const kyc = await KYC.deploy();
    console.log("Good");
    await kyc.deployed();
    console.log("KYC Project deployed to: "+ kyc.address);


}

main().then(()=>process.exit(0)).catch((error)=>{
console.log(error);
process.exit(1);

})