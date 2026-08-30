import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/test/rls.integration.test.ts', 'src/test/pos-price-loyalty.integration.test.ts', 'src/test/courier.integration.test.ts'],
    environment: 'node',
    globals: true,
    setupFiles: [],
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
