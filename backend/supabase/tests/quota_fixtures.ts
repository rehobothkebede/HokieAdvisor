import type { QuotaDecision } from "../functions/_shared/quota.ts";

/** For tests that aren't about quotas: every extraction is allowed. */
export const allowExtraction = (): Promise<QuotaDecision> =>
  Promise.resolve({ status: "allowed", userUsed: 1, userLimit: 10 });
