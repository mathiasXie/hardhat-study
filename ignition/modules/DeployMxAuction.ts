import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
// npx hardhat clean && npx hardhat ignition deploy ignition/modules/DeployMxAuction.ts --network sepolia
const DeployMxAuctionModule = buildModule("DeployMxAuctionModule",
  (m) => {
    /**
     * 1️⃣ 部署 MockAggregator
     */
    // const mockEthUsd = m.contract(
    //     "MockAggregator", 
    //     [
    //         8,                     // decimals
    //         3000n * 10n ** 8n      // ETH/USD = 3000
    //     ],
    //     {
    //         id: "MockAggregator_ETH_USD"
    //     }
    // );

    // const mockUsdcUsd = m.contract(
    //     "MockAggregator", 
    //     [
    //         8,
    //         1n * 10n ** 8n
    //     ],
    //     {
    //         id: "MockAggregator_USDC_USD"
    //     }
    // );

    /**
     * 2️⃣ 部署 ERC20 / ERC721
     */
    const mxToken = m.contract("MxToken", [
      "Mx Token",
      "MXT",
      18
    ]);

    const mxNFT = m.contract("MxNFT", [
      "Mx NFT",
      "MXNFT"
    ]);

    /**
     * 3️⃣ 部署 Auction Logic（实现合约）
     */
    const auctionImpl = m.contract("MxNFTAuction");

    /**
     * 4️⃣ 部署 UUPS Proxy
     *
     * UUPS 的本质：
     * - Proxy = ERC1967Proxy
     * - initialize 在部署时 delegatecall
     */
    const auctionProxy = m.contract(
      "ERC1967Proxy",
      [
        auctionImpl,
        m.encodeFunctionCall(auctionImpl, "initialize", [
          m.getAccount(0), // owner / admin
        ]),
      ],
      { id: "MxNFTAuctionProxy" }
    );

    /**
     * 5️⃣ 把 proxy 当成 MxNFTAuction 来用
     */
    const auction = m.contractAt(
      "MxNFTAuction",
      auctionProxy,
      { id: "MxNFTAuctionInstance" }
    );

    return {
    //   mockEthUsd,
    //   mockUsdcUsd,
      mxToken,
      mxNFT,
      auctionImpl,
      auctionProxy,
      auction,
    };
  }
);

export default DeployMxAuctionModule;
