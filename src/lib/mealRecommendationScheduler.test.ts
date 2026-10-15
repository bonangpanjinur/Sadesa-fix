import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261015020000_meal_recommendation_templates.sql'), 'utf8');

describe('admin meal recommendation templates', () => {
  it('seeds defaults without overwriting admin customizations on re-apply', () => {
    expect(migration).toContain("'meal_time_recommendations'");
    expect(migration).toContain('ON CONFLICT (key) DO NOTHING');
  });

  it('uses saved title and message in scheduled push and supports per-period disable', () => {
    expect(migration).toContain("v_templates -> marked.meal_period ->> 'title'");
    expect(migration).toContain("v_templates -> marked.meal_period ->> 'body'");
    expect(migration).toContain("v_templates -> due.meal_period -> 'enabled'");
    expect(migration).toContain("WHEN 7 THEN 'pagi'");
    expect(migration).toContain("WHEN 12 THEN 'siang'");
    expect(migration).toContain("WHEN 16 THEN 'sore'");
    expect(migration).toContain("WHEN 19 THEN 'malam'");
  });

  it('preserves existing opt-in subscriptions, timezone resolution, idempotency ledger, and queue delivery', () => {
    expect(migration).toContain('FROM public.push_subscriptions AS ps');
    expect(migration).toContain('FROM pg_timezone_names AS tz');
    expect(migration).toContain('ON CONFLICT (user_id, local_date, meal_period) DO NOTHING');
    expect(migration).toContain("'meal_time_reminder'");
    expect(migration).toContain('public.notification_delivery_jobs');
  });
});
