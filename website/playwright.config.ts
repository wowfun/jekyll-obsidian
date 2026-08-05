import { defineConfig, devices } from "@playwright/test";

const snapshotEnvironment = process.env.GITHUB_ACTIONS === "true" ? "github-ubuntu" : "local-linux";

export default defineConfig({
  testDir: "tests/browser",
  testMatch: "*.spec.ts",
  fullyParallel: true,
  workers: process.env.CI ? 2 : 4,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? "github" : "line",
  snapshotPathTemplate:
    `{snapshotDir}/{testFileDir}/{testFileName}-snapshots/{arg}{-projectName}-${snapshotEnvironment}{ext}`,
  use: {
    baseURL: "http://127.0.0.1:4173",
    trace: "retain-on-failure"
  },
  projects: [
    {
      name: "desktop-chromium",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 1000 } }
    },
    {
      name: "mobile-chromium",
      use: { ...devices["Pixel 7"] }
    }
  ],
  webServer: {
    command: "node tests/browser/server.mjs",
    wait: { stdout: /WEBSITE_BROWSER_SERVER_READY/ },
    timeout: 15_000
  }
});
