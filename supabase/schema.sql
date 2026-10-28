-- Run in the Supabase SQL editor. All records are scoped to auth.uid().
create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  currency text not null default 'USD',
  theme text not null default 'dark' check (theme in ('dark','light','system')),
  notification_preferences jsonb not null default '{"due":true,"tasks":true}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.borrowers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  email text,
  address text,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.loans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  borrower_id uuid not null references public.borrowers(id) on delete cascade,
  amount numeric(14,2) not null check (amount > 0),
  issued_at date not null default current_date,
  due_date date,
  loan_type text not null default 'Personal Loan',
  interest_rate numeric(7,4) not null default 0 check (interest_rate >= 0),
  status text not null default 'active' check (status in ('active','paid','overdue','cancelled')),
  notes text not null default '',
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  loan_id uuid not null references public.loans(id) on delete cascade,
  amount numeric(14,2) not null check (amount > 0),
  paid_at date not null default current_date,
  method text not null default 'Cash',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.loan_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  loan_id uuid not null references public.loans(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.loan_timeline (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  loan_id uuid not null references public.loans(id) on delete cascade,
  event_type text not null,
  description text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  loan_id uuid not null references public.loans(id) on delete cascade,
  file_name text not null,
  storage_path text not null,
  content_type text not null,
  size_bytes bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  due_at date,
  priority text not null default 'medium' check (priority in ('low','medium','high')),
  status text not null default 'pending' check (status in ('pending','in_progress','complete')),
  recurring_task_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.recurring_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  frequency text not null check (frequency in ('daily','weekly','monthly')),
  priority text not null default 'medium' check (priority in ('low','medium','high')),
  next_due_at date not null default current_date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.tasks drop constraint if exists tasks_recurring_task_id_fkey;
alter table public.tasks add constraint tasks_recurring_task_id_fkey foreign key (recurring_task_id) references public.recurring_tasks(id) on delete set null;
create table if not exists public.task_occurrences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  recurring_task_id uuid not null references public.recurring_tasks(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  due_at date not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (recurring_task_id, due_at)
);
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null,
  related_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.reminder_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  loan_id uuid not null references public.loans(id) on delete cascade,
  action text not null,
  note text not null default '',
  contacted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists borrowers_user_name_idx on public.borrowers(user_id, full_name);
create index if not exists loans_user_due_idx on public.loans(user_id, due_date) where archived_at is null;
create index if not exists loans_borrower_idx on public.loans(borrower_id);
create index if not exists payments_loan_date_idx on public.payments(loan_id, paid_at desc);
create index if not exists tasks_user_due_idx on public.tasks(user_id, due_at);
create index if not exists notifications_user_read_idx on public.notifications(user_id, read_at);

-- Complete a recurring task by recording its occurrence and creating the next task.
create or replace function public.generate_next_task_occurrence()
returns trigger language plpgsql security invoker as $$
declare
  recurring public.recurring_tasks%rowtype;
  next_date date;
  occurrence_id uuid;
begin
  if new.status <> 'complete' or old.status = 'complete' or new.recurring_task_id is null then
    return new;
  end if;

  select * into recurring
  from public.recurring_tasks
  where id = new.recurring_task_id and user_id = auth.uid() and active;
  if not found then return new; end if;

  next_date := case recurring.frequency
    when 'daily' then coalesce(new.due_at, current_date) + 1
    when 'weekly' then coalesce(new.due_at, current_date) + 7
    else (coalesce(new.due_at, current_date) + interval '1 month')::date
  end;

  insert into public.task_occurrences(user_id, recurring_task_id, task_id, due_at, completed_at)
  values (new.user_id, recurring.id, new.id, coalesce(new.due_at, current_date), now())
  on conflict (recurring_task_id, due_at) do nothing
  returning id into occurrence_id;

  if occurrence_id is not null then
    insert into public.tasks(user_id, title, description, due_at, priority, status, recurring_task_id)
    values (new.user_id, recurring.title, recurring.description, next_date, recurring.priority, 'pending', recurring.id);
    update public.recurring_tasks set next_due_at = next_date where id = recurring.id;
  end if;

  return new;
end;
$$;
drop trigger if exists tasks_generate_next_occurrence on public.tasks;
create trigger tasks_generate_next_occurrence after update of status on public.tasks
for each row execute function public.generate_next_task_occurrence();

-- Keep status paid when all principal is repaid; overdue is derived by due date in the UI.
create or replace function public.refresh_loan_payment_status()
returns trigger language plpgsql security invoker as $$
declare target uuid; principal numeric; paid numeric;
begin
  if tg_op = 'DELETE' then
    target := old.loan_id;
  else
    target := new.loan_id;
  end if;
  select amount into principal from public.loans where id = target;
  select coalesce(sum(amount), 0) into paid from public.payments where loan_id = target;
  update public.loans set status = case when paid >= principal then 'paid' when status = 'paid' then 'active' else status end
    where id = target and status <> 'cancelled';

  if tg_op = 'UPDATE' and old.loan_id is distinct from new.loan_id then
    target := old.loan_id;
    select amount into principal from public.loans where id = target;
    select coalesce(sum(amount), 0) into paid from public.payments where loan_id = target;
    update public.loans set status = case when paid >= principal then 'paid' when status = 'paid' then 'active' else status end
      where id = target and status <> 'cancelled';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists payments_refresh_loan_status on public.payments;
create trigger payments_refresh_loan_status after insert or update or delete on public.payments
for each row execute function public.refresh_loan_payment_status();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name) values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name',''));
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

do $$
declare tab text;
begin
  foreach tab in array array['profiles','borrowers','loans','payments','loan_notes','loan_timeline','attachments','tasks','task_occurrences','recurring_tasks','notifications','reminder_logs'] loop
    execute format('drop trigger if exists set_updated_at on public.%I', tab);
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()', tab);
    execute format('alter table public.%I enable row level security', tab);
    if tab = 'profiles' then
      execute 'drop policy if exists "profile owner access" on public.profiles';
      execute 'create policy "profile owner access" on public.profiles for all using (id = auth.uid()) with check (id = auth.uid())';
    else
      execute format('drop policy if exists "owner access" on public.%I', tab);
      if tab = 'borrowers' or tab = 'recurring_tasks' or tab = 'notifications' then
        execute format('create policy "owner access" on public.%I for all using (user_id = auth.uid()) with check (user_id = auth.uid())', tab);
      elsif tab = 'loans' then
        execute 'create policy "owner access" on public.loans for all using (user_id = auth.uid()) with check (user_id = auth.uid() and exists (select 1 from public.borrowers b where b.id = borrower_id and b.user_id = auth.uid()))';
      elsif tab in ('payments','loan_notes','loan_timeline','attachments','reminder_logs') then
        execute format(
          'create policy "owner access" on public.%I for all using (user_id = auth.uid() and exists (select 1 from public.loans l where l.id = loan_id and l.user_id = auth.uid())) with check (user_id = auth.uid() and exists (select 1 from public.loans l where l.id = loan_id and l.user_id = auth.uid()))',
          tab
        );
      elsif tab = 'tasks' then
        execute 'create policy "owner access" on public.tasks for all using (user_id = auth.uid() and (recurring_task_id is null or exists (select 1 from public.recurring_tasks r where r.id = recurring_task_id and r.user_id = auth.uid()))) with check (user_id = auth.uid() and (recurring_task_id is null or exists (select 1 from public.recurring_tasks r where r.id = recurring_task_id and r.user_id = auth.uid())))';
      elsif tab = 'task_occurrences' then
        execute 'create policy "owner access" on public.task_occurrences for all using (user_id = auth.uid() and exists (select 1 from public.recurring_tasks r where r.id = recurring_task_id and r.user_id = auth.uid()) and (task_id is null or exists (select 1 from public.tasks t where t.id = task_id and t.user_id = auth.uid()))) with check (user_id = auth.uid() and exists (select 1 from public.recurring_tasks r where r.id = recurring_task_id and r.user_id = auth.uid()) and (task_id is null or exists (select 1 from public.tasks t where t.id = task_id and t.user_id = auth.uid())))';
      end if;
    end if;
  end loop;
end $$;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('loan-attachments','loan-attachments',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 10485760,
  allowed_mime_types = array['application/pdf','image/jpeg','image/png','image/webp'];
drop policy if exists "users manage own loan files" on storage.objects;
create policy "users manage own loan files" on storage.objects for all to authenticated
using (bucket_id = 'loan-attachments' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'loan-attachments' and (storage.foldername(name))[1] = auth.uid()::text);
