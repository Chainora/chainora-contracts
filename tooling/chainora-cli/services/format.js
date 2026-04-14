// @ts-check

import pc from "picocolors";

/**
 * @param {string} title
 */
export function printHeader(title) {
  console.log("");
  console.log(pc.bold(pc.cyan(title)));
}

/**
 * @param {string} label
 * @param {string | number | bigint | boolean | undefined} value
 */
export function printField(label, value) {
  const rendered = value === undefined ? pc.dim("(trống)") : String(value);
  console.log(`${pc.bold(label)}: ${rendered}`);
}

/**
 * @param {string} message
 */
export function printSuccess(message) {
  console.log(pc.green(message));
}

/**
 * @param {string} message
 */
export function printWarning(message) {
  console.log(pc.yellow(message));
}

/**
 * @param {string} message
 */
export function printInfo(message) {
  console.log(pc.blue(message));
}

/**
 * @param {string} value
 */
export function shortAddress(value) {
  if (value.length < 12) return value;
  return `${value.slice(0, 6)}...${value.slice(-4)}`;
}

