-- Manajemen sengketa transaksi jasa
create table if not exists public.service_disputes (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.service_requests(id) on delete cascade,
  opened_by uuid not null references auth.users(id) on delete restrict,
  requester_id uuid not null references auth.users(id) on delete restrict,
  provider_id uuid not null references auth.users(id) on delete restrict,
  reason text not null,
  amount numeric(14,2),
  evidence_urls jsonb not null default '[]'::jsonb,
  status text not null default 'OPEN' check (status in ('OPEN','IN_REVIEW','WAITING_PARTIES','REFUND_APPROVED','RELEASE_APPROVED','RESOLVED','CLOSED','REJECTED')),
  admin_note text,
  resolution text,
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_service_disputes_status on public.service_disputes(status, created_at desc);
create index if not exists idx_service_disputes_participants on public.service_disputes(requester_id, provider_id);

alter table public.service_disputes enable row level security;
create policy "participants read service disputes" on public.service_disputes for select using (opened_by = auth.uid() or requester_id = auth.uid() or provider_id = auth.uid() or public.is_admin(auth.uid()));
create policy "participants create service disputes" on public.service_disputes for insert with check ((opened_by = auth.uid()) and (requester_id = auth.uid() or provider_id = auth.uid()));
create policy "admins manage service disputes" on public.service_disputes for update using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));
create policy "admins delete service disputes" on public.service_disputes for delete using (public.is_admin(auth.uid()));
