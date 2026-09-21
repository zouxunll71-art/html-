export function normalizeUsage(value, now = Date.now()) {
  const buckets = value.rateLimitsByLimitId && Object.keys(value.rateLimitsByLimitId).length ? Object.entries(value.rateLimitsByLimitId) : value.rateLimits ? [[value.rateLimits.limitId || 'codex', value.rateLimits]] : [];
  return { updatedAt: now, ordinaryUsageAllowed: value.ordinaryUsageAllowed ?? null, buckets: buckets.filter(([, b]) => b).map(([id, b]) => ({
    id, name: b.limitName || (id === 'codex' ? 'Codex' : id), model: b.normalModelSlug || null, plan: b.planType || null,
    windows: ['primary', 'secondary'].flatMap(key => {
      const w = b[key]; if (!w || typeof w.usedPercent !== 'number' || !Number.isFinite(w.usedPercent)) return [];
      return [{ key, remaining: Math.max(0, Math.min(100, 100 - w.usedPercent)), minutes: w.windowDurationMins ?? null, resetsAt: w.resetsAt ?? null }];
    }), credits: b.credits ? { balance: b.credits.balance, unlimited: b.credits.unlimited } : null,
  })) };
}
