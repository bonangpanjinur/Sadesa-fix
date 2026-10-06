import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  resolve(process.cwd(), 'archive/supabase/migrations/20261006170000_chat_message_web_push.sql'),
  'utf8',
);

describe('chat Web Push delivery contract', () => {
  it('preserves in-app alerts and only queues push for subscribed recipients', () => {
    expect(migration).toContain('INSERT INTO public.notifications');
    expect(migration).toContain('FROM public.push_subscriptions');
    expect(migration).toContain('WHERE user_id = p_recipient_id');
    expect(migration).toContain("'new_chat_message'");
    expect(migration).toContain("'type', 'chat'");
    expect(migration).toContain("'url', v_link");
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.send_chat_notification(uuid, uuid, uuid, text, text)');
    expect(migration).toContain('FROM PUBLIC, anon, authenticated');
  });

  it('does not expose the message preview in the OS lock-screen push body', () => {
    expect(migration).toContain("'body', 'Anda menerima pesan baru. Buka SaDesa untuk membalas.'");
    expect(migration).not.toMatch(/'body'\s*,\s*[^\n]*p_preview/i);
  });

  it('deduplicates one push per message/recipient and wakes the durable worker', () => {
    expect(migration).toContain("'chat:' || p_message_id::text || ':' || p_recipient_id::text");
    expect(migration).toContain('notification_jobs_chat_push_dedupe_uidx');
    expect(migration).toContain('ON CONFLICT (dedupe_key)');
    expect(migration).toContain('dispatch_urgent_chat_push_job_trigger');
    expect(migration).toContain("NEW.template_key = 'new_chat_message'");
    expect(migration).toContain('PERFORM public.dispatch_notification_delivery_jobs()');
  });
});
