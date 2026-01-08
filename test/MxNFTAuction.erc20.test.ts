import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { zeroAddress } from "viem";

describe("MxNFTAuction - ERC20 auction", function () {
  it("outbid -> withdraw -> settle", async function () {
    const { viem } = await network.connect();

    const [seller, bidderA, bidderB] = await viem.getWalletClients();
    const publicClient = await viem.getPublicClient();

    const erc20 = await viem.deployContract("MxToken", ["MxToken", "MX", 1000000n * 10n ** 18n]);
    const erc721 = await viem.deployContract("MxNFT", ["MxNFT", "MNFT"]);
    const auction = await viem.deployContract("MxNFTAuction", []);

    // mint NFT
    await erc721.write.mint([seller.account.address]);

    // mint ERC20
    const amount = 1_000n * 10n ** 18n;
    await erc20.write.mint([bidderA.account.address, amount]);
    await erc20.write.mint([bidderB.account.address, amount]);
    console.log("bidder a balance:", await erc20.read.balanceOf([bidderA.account.address]));

    // approvals
    await erc721.write.approve([auction.address, 0n], { account: seller.account });
    await erc20.write.approve([auction.address, amount], { account: bidderA.account });
    await erc20.write.approve([auction.address, amount], { account: bidderB.account });

    const mockEthFeed = await viem.deployContract("MockAggregator", [
      3_000n * 10n ** 8n, // $3000
      8
    ]);

    const mockErc20Feed = await viem.deployContract("MockAggregator", [
      1n * 10n ** 8n, // $1
      8
    ]);

    await auction.write.setPriceFeed([0, mockEthFeed.address]);   // ETH
    await auction.write.setPriceFeed([1, mockErc20Feed.address]); // ERC20

    // start auction
    await auction.write.startAuction(
      [erc721.address, 0n, 1, erc20.address, 100n * 10n ** 18n, 3600n],
      { account: seller.account }
    );
    // bids
    await auction.write.bidERC20([0n, 200n * 10n ** 18n], { account: bidderA.account });
    await auction.write.bidERC20([0n, 300n * 10n ** 18n], { account: bidderB.account });

    // pending return
    const pending = await auction.read.pendingReturns([0n, bidderA.account.address]);
    assert.equal(pending, 200n * 10n ** 18n);

    // withdraw
    const before = await erc20.read.balanceOf([bidderA.account.address]) as bigint;
    await auction.write.withdraw([0n], { account: bidderA.account });
    const after = await erc20.read.balanceOf([bidderA.account.address]) as bigint;

    assert.equal(after - before, 200n * 10n ** 18n);

    const testClient = await viem.getTestClient();

    // fast forward
    await testClient.increaseTime({ seconds: 4000 });
    await testClient.mine({ blocks: 1 });

    // settle
    await auction.write.settle([0n]);

    const owner = await erc721.read.ownerOf([0n]);
    assert.equal((owner as string).toLowerCase(), bidderB.account.address.toLowerCase());
  });
});


describe("MxNFTAuction - ETH auction", function () {
  it("outbid -> withdraw -> settle", async function () {
    const { viem } = await network.connect();

    const [seller, bidderA, bidderB] = await viem.getWalletClients();
    const publicClient = await viem.getPublicClient();

    const erc721 = await viem.deployContract("MxNFT", ["MxNFT", "MNFT"]);
    const auction = await viem.deployContract("MxNFTAuction", []);

    // mint NFT
    await erc721.write.mint([seller.account.address]);

    // approvals
    await erc721.write.approve([auction.address, 0n], { account: seller.account });

    const mockEthFeed = await viem.deployContract("MockAggregator", [
      3_000n * 10n ** 8n, // $3000
      8
    ]);

    const mockErc20Feed = await viem.deployContract("MockAggregator", [
      1n * 10n ** 8n, // $1
      8
    ]);

    await auction.write.setPriceFeed([0, mockEthFeed.address]);   // ETH
    await auction.write.setPriceFeed([1, mockErc20Feed.address]); // ERC20

    // start auction
    await auction.write.startAuction(
      [erc721.address, 0n, 0, zeroAddress, 10n, 3600n],
      { account: seller.account }
    );
    // bids
    await auction.write.bidETH([0n], { account: bidderA.account, value: 18n });
    await auction.write.bidETH([0n], { account: bidderB.account, value: 19n });

    // pending return
    const pending = await auction.read.pendingReturns([0n, bidderA.account.address]) as bigint;
    assert.equal(pending, 18n);

    // withdraw — use ETH balance before/after and account for gas cost
    const beforeBalance = await publicClient.getBalance({ address: bidderA.account.address });
    const txHash = await auction.write.withdraw([0n], { account: bidderA.account }) as `0x${string}`;
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
    const gasUsed = BigInt(receipt.gasUsed ?? 0n);
    const effectiveGasPrice = BigInt(receipt.effectiveGasPrice ?? 0n);
    const gasCost = gasUsed * effectiveGasPrice;
    const afterBalance = await publicClient.getBalance({ address: bidderA.account.address });

    // net change should equal refunded amount minus tx gas cost
    assert.equal(afterBalance - beforeBalance, pending - gasCost);

    // pendingReturns should be cleared
    const pendingAfter = await auction.read.pendingReturns([0n, bidderA.account.address]) as bigint;
    assert.equal(pendingAfter, 0n);

    const testClient = await viem.getTestClient();

    // fast forward
    await testClient.increaseTime({ seconds: 4000 });
    await testClient.mine({ blocks: 1 });

    // settle
    await auction.write.settle([0n]);

    const owner = await erc721.read.ownerOf([0n]);
    assert.equal((owner as string).toLowerCase(), bidderB.account.address.toLowerCase());
  });
});
