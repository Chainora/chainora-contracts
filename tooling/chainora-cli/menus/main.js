// @ts-check

import { choose } from "../prompts/common.js";

export function chooseMainMenu() {
  return choose({
    message: "Chọn workflow",
    choices: [
      { name: "Deploy", value: "deploy" },
      { name: "Admin", value: "admin" },
      { name: "Timelock Utilities", value: "timelock" },
      { name: "Thoát", value: "exit" }
    ]
  });
}

export function chooseDeployMenu() {
  return choose({
    message: "Chọn flow deploy",
    choices: [
      { name: "Bootstrap Core", value: "bootstrapCore" },
      { name: "Deploy Timelock", value: "deployTimelock" },
      { name: "Deploy Registry", value: "deployRegistry" },
      { name: "Deploy Device Adapter", value: "deployDeviceAdapter" },
      { name: "Deploy Reputation Adapter", value: "deployReputationAdapter" },
      { name: "Deploy Pool Implementation", value: "deployPoolImplementation" },
      { name: "Deploy Factory", value: "deployFactory" },
      { name: "Deploy ChainoraTestUSD", value: "deployChainoraTestUSD" },
      { name: "Quay lại", value: "back" }
    ]
  });
}

export function chooseAdminGroup() {
  return choose({
    message: "Chọn nhóm admin",
    choices: [
      { name: "Registry", value: "registry" },
      { name: "Factory", value: "factory" },
      { name: "Device Adapter", value: "deviceAdapter" },
      { name: "Reputation Adapter", value: "reputationAdapter" },
      { name: "Quay lại", value: "back" }
    ]
  });
}

export function chooseTimelockMenu() {
  return choose({
    message: "Chọn tiện ích timelock",
    choices: [
      { name: "Inspect Operation", value: "inspect" },
      { name: "Cancel Operation", value: "cancel" },
      { name: "Quay lại", value: "back" }
    ]
  });
}
