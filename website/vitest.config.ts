import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "happy-dom",
    include: ["tests/frontend/**/*.test.ts"],
    // Bound DOM workers: unrestricted cold imports of D3 can time out under
    // CPU and filesystem contention without indicating a graph regression.
    maxWorkers: 4,
    clearMocks: true,
    restoreMocks: true
  }
});
