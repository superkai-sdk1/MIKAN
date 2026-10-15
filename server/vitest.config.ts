import { defineConfig } from 'vitest/config';

// The production host's OS clock is not in the studio timezone. Run tests with a "wrong" OS timezone
// (worker processes inherit it) so any accidental reliance on process-local time fails loudly.
process.env.TZ = 'Asia/Tomsk';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
    testTimeout: 20_000,
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      exclude: ['src/index.ts'],
      reporter: ['text', 'text-summary'],
    },
  },
});
