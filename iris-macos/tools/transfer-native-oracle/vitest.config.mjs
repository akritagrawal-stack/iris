// This oracle lives beside Iris rather than inside the NitroAI checkout. Keep
// the config dependency-free so it can be run with any explicitly approved
// NitroAI target's Vitest installation.
export default {
  test: {
    environment: "node",
    include: ["/Users/akrit/Documents/iris-acceptance-integration-20260913/iris-macos/tools/transfer-native-oracle/transfer.test.mjs"],
  },
};
