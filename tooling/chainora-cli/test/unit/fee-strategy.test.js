// @ts-check

import assert from "node:assert/strict";
import test from "node:test";

import { detectFeeStrategy } from "../../services/chain.js";

test("detectFeeStrategy recognizes zero-fee legacy rpc", async () => {
  const mockClient = /** @type {any} */ ({
    getGasPrice: async () => 0n,
    getBlock: async () => ({ baseFeePerGas: 0n }),
    request: async () => "0x0"
  });
  const strategy = await detectFeeStrategy(mockClient);

  assert.equal(strategy.kind, "legacy");
  assert.equal(strategy.gasPrice, 0n);
  assert.equal(strategy.isZeroFee, true);
});
