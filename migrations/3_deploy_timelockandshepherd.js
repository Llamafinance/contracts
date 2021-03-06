const LlamaToken = artifacts.require("LlamaToken");
const MasterShepherd = artifacts.require("MasterShepherd");
const Timelock = artifacts.require("Timelock");

let devAddress = "0x80D278Bd92a60D843E4047B52ff104420e2643A2"
let feeAdddress = "0x4600a7e1F43216D95C4fD1e000b69484180c45C1"

module.exports = async function (deployer) {
  // 1st deployment
  //const Time = await deployer.deploy(Timelock, devAddress, 60)//60 secondi PER LA TESTNET di delay iniziale
  const Time = await deployer.deploy(Timelock, devAddress, 21600)//6 ORE PER LA MAINNET di delay iniziale
  /*
  Master ctor params:
    LlamaToken _lama,        
    address _devaddr,
    address _feeAddress,
    uint256 _lamaPerBlock           
  */
  const Lama = await LlamaToken.deployed();
  const lamaPerBlock = "1000000000000000000";
  const Shepherd = await deployer.deploy(MasterShepherd, Lama.address, devAddress, feeAdddress, lamaPerBlock)  
  
  
}