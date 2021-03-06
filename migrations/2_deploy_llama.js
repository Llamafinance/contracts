const LlamaToken = artifacts.require("LlamaToken");

module.exports = async function (deployer) {
  // 1st deployment
  const Lama = await deployer.deploy(LlamaToken)  
}