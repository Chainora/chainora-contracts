// @ts-check

import assert from "node:assert/strict";
import test from "node:test";

import { buildBaseSalt, buildCandidateSalt, computeOperationId } from "../../services/timelock.js";

test("timelock salt derivation is deterministic and label-sensitive", () => {
  const baseA = buildBaseSalt(
    31337n,
    "0x0000000000000000000000000000000000000001",
    "0x1234",
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "setPoolImplementation"
  );
  const baseB = buildBaseSalt(
    31337n,
    "0x0000000000000000000000000000000000000001",
    "0x1234",
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    "setStablecoin"
  );

  assert.equal(baseA, buildBaseSalt(31337n, "0x0000000000000000000000000000000000000001", "0x1234", "0x0000000000000000000000000000000000000000000000000000000000000000", "setPoolImplementation"));
  assert.notEqual(baseA, baseB);
  assert.notEqual(buildCandidateSalt(baseA, 0), buildCandidateSalt(baseA, 1));
  assert.notEqual(
    computeOperationId("0x0000000000000000000000000000000000000001", "0x1234", "0x0000000000000000000000000000000000000000000000000000000000000000", buildCandidateSalt(baseA, 0)),
    computeOperationId("0x0000000000000000000000000000000000000001", "0x1234", "0x0000000000000000000000000000000000000000000000000000000000000000", buildCandidateSalt(baseA, 1))
  );
});
