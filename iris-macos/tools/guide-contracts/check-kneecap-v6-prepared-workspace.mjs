import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const proposalURL = new URL("./kneecap-v6-prepared-workspace.proposal.json", import.meta.url);
const guide = JSON.parse(readFileSync(fileURLToPath(proposalURL), "utf8"));
const expectedCommit = "fc48ba487a1e0d0cd10b30d6600acd2895ffdbed";

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

requireCondition(guide.appSlug === "kneecap" && guide.version === 6, "expected Kneecap v6 proposal");
requireCondition(guide.sourceCommit === expectedCommit, "proposal must retain the reviewed source pin");
const macOSIOSBranch = guide.branches.find(branch => branch.platform === "macos" && branch.target === "ios");
requireCondition(macOSIOSBranch, "proposal needs the Mac + iPhone branch");
const xcodePrerequisite = macOSIOSBranch.setupSteps.find(step => step.id === "install-xcode");
requireCondition(xcodePrerequisite?.kind === "open" && xcodePrerequisite.tool === "xcode",
  "proposal must preserve the full Xcode prerequisite");
requireCondition(typeof xcodePrerequisite.href === "string" && xcodePrerequisite.href.length > 0,
  "full Xcode prerequisite needs a reader-owned installation route");

for (const branch of guide.branches) {
  for (const step of branch.steps) {
    const command = step.command ?? "";
    requireCondition(!step.workingDirectory, `${step.id} must not use legacy workingDirectory`);
    requireCondition(!/\bcd\s+~\/kneecap(?:\b|\/)/.test(command), `${step.id} forces ~/kneecap`);
    if (["install-deps", "build-editor", "sync-ios", "open-project"].includes(step.id)) {
      requireCondition(step.workspace?.kind === "prepared-project", `${step.id} needs prepared-project workspace`);
      requireCondition(typeof step.workspace.relativePath === "string", `${step.id} needs relative workspace path`);
    }
  }
}

console.log("kneecap v6 prepared-workspace proposal checks passed");
