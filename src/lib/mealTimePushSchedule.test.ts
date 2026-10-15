import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(resolve(process.cwd(), 'archive/supabase/migrations/20261015000000_meal_time_push_reminders.sql'), 'utf8');

describe('scheduled meal-time push reminders', () => {
  it('keeps each subscription timezone and schedules four local meal times', () => {
    expect(migration).toContain("ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'Asia/Jakarta'");
    expect(migration).toContain("WHEN 7 THEN 'pagi'");
    expect(migration).toContain("WHEN 12 THEN 'siang'");
    expect(migration).toContain("WHEN 16 THEN 'sore'");
    expect(migration).toContain("WHEN 19 THEN 'malam'");
    expect(migration).toContain("'sadesa-meal-time-push-reminders'");
    expect(migration).toContain("'* * * * *'");
  });

  it('only queues for push subscribers and deduplicates each user period and timezone', () => {
    expect(migration).toContain('FROM public.push_subscriptions AS ps');
    expect(migration).toContain('ps.p256dh IS NOT NULL');
    expect(migration).toContain('ps.auth IS NOT NULL');
    expect(migration).toContain('PRIMARY KEY (user_id, local_date, meal_period)');
    expect(migration).toContain('ON CONFLICT (user_id, local_date, meal_period) DO NOTHING');
    expect(migration).toContain("'push',\n    'meal_time_reminder'");
    expect(migration).toContain('public.notification_delivery_jobs');
  });
});
