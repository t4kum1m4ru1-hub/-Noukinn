-- のう筋（Noukin） Initial Schema & Row-Level Security (RLS)
-- Apply via Supabase SQL Editor or `supabase db push`

create extension if not exists pgcrypto;

-- 1. user_profiles
create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  gender text not null default 'male'
    check (gender in ('male', 'female')),
  birth_year integer not null default 1995
    check (birth_year between 1900 and 2100),
  experience text not null default 'beginner'
    check (experience in ('beginner', 'intermediate')),
  body_weight_kg double precision not null default 65.0
    check (body_weight_kg > 0),
  purpose text not null default 'body_make_male'
    check (purpose in (
      'body_make_male',
      'body_make_female',
      'health',
      'diet',
      'tennis',
      'windsurfing'
    )),
  is_first_time boolean not null default true,
  session_count integer not null default 1
    check (session_count >= 0),
  updated_at timestamptz not null default now()
);

-- 2. muscle_states
create table if not exists public.muscle_states (
  user_id uuid not null references auth.users(id) on delete cascade,
  muscle_id text not null,
  blank_days integer not null default 4
    check (blank_days >= 0),
  stimulation_days double precision not null default 2.0
    check (stimulation_days >= 0),
  priority_p integer not null default 10
    check (priority_p >= 0),
  is_injured boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, muscle_id)
);

-- 3. machine_history
create table if not exists public.machine_history (
  user_id uuid not null references auth.users(id) on delete cascade,
  machine_id text not null,
  sessions_since_used integer not null default 4
    check (sessions_since_used >= 0),
  last_weight_kg double precision
    check (last_weight_kg is null or last_weight_kg > 0),
  last_feedback text
    check (last_feedback is null or last_feedback in ('too_light', 'just_right', 'too_hard')),
  updated_at timestamptz not null default now(),
  primary key (user_id, machine_id)
);

-- 4. workout_sessions
create table if not exists public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  completed_at timestamptz not null,
  duration_course text not null
    check (duration_course in ('short_20', 'standard_45', 'full_60')),
  condition text not null
    check (condition in ('great', 'normal', 'tired')),
  time_slot text not null
    check (time_slot in ('morning', 'daytime', 'evening', 'night')),
  focus_muscle_id text,
  feedback text not null
    check (feedback in ('too_light', 'just_right', 'too_hard')),
  exercises_json jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

-- Indexes
create index if not exists idx_workout_sessions_user_completed_at
  on public.workout_sessions (user_id, completed_at asc);

create index if not exists idx_muscle_states_user_id
  on public.muscle_states (user_id);

create index if not exists idx_machine_history_user_id
  on public.machine_history (user_id);

-- Row-Level Security (RLS)
alter table public.user_profiles enable row level security;
alter table public.muscle_states enable row level security;
alter table public.machine_history enable row level security;
alter table public.workout_sessions enable row level security;

-- RLS Policies: user_profiles
create policy "user_profiles_select_own"
  on public.user_profiles for select
  using (auth.uid() = user_id);

create policy "user_profiles_insert_own"
  on public.user_profiles for insert
  with check (auth.uid() = user_id);

create policy "user_profiles_update_own"
  on public.user_profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "user_profiles_delete_own"
  on public.user_profiles for delete
  using (auth.uid() = user_id);

-- RLS Policies: muscle_states
create policy "muscle_states_select_own"
  on public.muscle_states for select
  using (auth.uid() = user_id);

create policy "muscle_states_insert_own"
  on public.muscle_states for insert
  with check (auth.uid() = user_id);

create policy "muscle_states_update_own"
  on public.muscle_states for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "muscle_states_delete_own"
  on public.muscle_states for delete
  using (auth.uid() = user_id);

-- RLS Policies: machine_history
create policy "machine_history_select_own"
  on public.machine_history for select
  using (auth.uid() = user_id);

create policy "machine_history_insert_own"
  on public.machine_history for insert
  with check (auth.uid() = user_id);

create policy "machine_history_update_own"
  on public.machine_history for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "machine_history_delete_own"
  on public.machine_history for delete
  using (auth.uid() = user_id);

-- RLS Policies: workout_sessions
create policy "workout_sessions_select_own"
  on public.workout_sessions for select
  using (auth.uid() = user_id);

create policy "workout_sessions_insert_own"
  on public.workout_sessions for insert
  with check (auth.uid() = user_id);

create policy "workout_sessions_update_own"
  on public.workout_sessions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "workout_sessions_delete_own"
  on public.workout_sessions for delete
  using (auth.uid() = user_id);
