-- ==============================================================================
-- HereNow: Universal Bluetooth Low Energy Proximity Presence Database Schema
-- Compatible with Supabase (PostgreSQL with Row Level Security & Realtime)
-- Works universally for Companies, Travel, Education, Events, Sports, Clubs, etc.
-- ==============================================================================

-- Enable UUID extension if not already enabled
create extension if not exists "uuid-ossp";

-- 1. USERS TABLE (Universal Profiles)
create table if not exists public.users (
    id uuid primary key default uuid_generate_v4(),
    auth_id uuid references auth.users(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    avatar_url text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Index for auth lookup
create index if not exists idx_users_auth_id on public.users(auth_id);

-- 2. SESSIONS TABLE (Universal Group Presence Sessions)
create table if not exists public.sessions (
    id uuid primary key default uuid_generate_v4(),
    organizer_id uuid references public.users(id) on delete set null,
    name text not null,
    description text,
    category text default 'COMPANY' check (category in ('COMPANY', 'TRAVEL', 'EDUCATION', 'EVENT', 'SPORTS', 'CLUB', 'FRIENDS', 'FAMILY', 'OTHER', 'General')),
    join_code varchar(16) not null unique,
    start_time timestamp with time zone not null,
    end_time timestamp with time zone not null,
    proximity_threshold text default 'normal' check (proximity_threshold in ('near', 'normal', 'wide')),
    meeting_latitude double precision,
    meeting_longitude double precision,
    geofence_radius double precision, -- in meters, optional
    status text default 'active' check (status in ('scheduled', 'active', 'completed')),
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create index if not exists idx_sessions_join_code on public.sessions(join_code);
create index if not exists idx_sessions_organizer_id on public.sessions(organizer_id);
create index if not exists idx_sessions_status on public.sessions(status);

-- 3. SESSION MEMBERS TABLE (Group Membership)
create table if not exists public.session_members (
    id uuid primary key default uuid_generate_v4(),
    session_id uuid references public.sessions(id) on delete cascade not null,
    user_id uuid references public.users(id) on delete cascade not null,
    role text default 'member' check (role in ('organizer', 'member')),
    status text default 'missing' check (status in ('present', 'possibly_away', 'missing', 'manually_confirmed', 'left')),
    last_verified_at timestamp with time zone,
    device_fingerprint text,
    joined_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(session_id, user_id)
);

create index if not exists idx_session_members_session_id on public.session_members(session_id);
create index if not exists idx_session_members_user_id on public.session_members(user_id);
create index if not exists idx_session_members_status on public.session_members(status);

-- 4. PRESENCE CHECKS TABLE (Ephemeral rotating checks initiated by organizer)
create table if not exists public.presence_checks (
    id uuid primary key default uuid_generate_v4(),
    session_id uuid references public.sessions(id) on delete cascade not null,
    initiator_id uuid references public.users(id) on delete set null,
    check_token text not null, -- Rotating ephemeral token
    status text default 'active' check (status in ('active', 'completed', 'expired')),
    started_at timestamp with time zone default timezone('utc'::text, now()) not null,
    expires_at timestamp with time zone not null
);

create index if not exists idx_presence_checks_session on public.presence_checks(session_id);
create index if not exists idx_presence_checks_status on public.presence_checks(status);

-- 5. PRESENCE VERIFICATIONS TABLE (Individual cryptographic proximity proof records)
create table if not exists public.presence_verifications (
    id uuid primary key default uuid_generate_v4(),
    check_id uuid references public.presence_checks(id) on delete cascade not null,
    session_id uuid references public.sessions(id) on delete cascade not null,
    user_id uuid references public.users(id) on delete cascade not null,
    verification_token_hash text not null,
    verification_method text default 'ble' check (verification_method in ('ble', 'manual', 'qr_location')),
    verified_at timestamp with time zone default timezone('utc'::text, now()) not null,
    rssi integer, -- signal strength indication, not physical distance
    metadata jsonb default '{}'::jsonb,
    unique(check_id, user_id)
);

create index if not exists idx_presence_verifications_check on public.presence_verifications(check_id);
create index if not exists idx_presence_verifications_session_user on public.presence_verifications(session_id, user_id);

-- 6. PRESENCE EVENTS TABLE (Universal Audit trail)
create table if not exists public.presence_events (
    id uuid primary key default uuid_generate_v4(),
    session_id uuid references public.sessions(id) on delete cascade not null,
    user_id uuid references public.users(id) on delete set null,
    event_type text not null, -- 'joined', 'verified_ble', 'manually_confirmed', 'marked_missing', 'marked_away', 'left_session'
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    metadata jsonb default '{}'::jsonb
);

create index if not exists idx_presence_events_session on public.presence_events(session_id);

-- ==============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

alter table public.users enable row level security;
alter table public.sessions enable row level security;
alter table public.session_members enable row level security;
alter table public.presence_checks enable row level security;
alter table public.presence_verifications enable row level security;
alter table public.presence_events enable row level security;

-- USERS POLICIES
create policy "Users can view profile of session participants" on public.users
    for select using (true);

create policy "Users can update own profile" on public.users
    for update using (auth.uid() = auth_id);

create policy "Users can insert own profile" on public.users
    for insert with check (auth.uid() = auth_id or auth.uid() is null);

-- SESSIONS POLICIES
create policy "Users can view sessions" on public.sessions
    for select using (true);

create policy "Organizers can create sessions" on public.sessions
    for insert with check (true);

create policy "Users can update sessions" on public.sessions
    for update using (true);

-- SESSION MEMBERS POLICIES
create policy "Users can view session members" on public.session_members
    for select using (true);

create policy "Users can join sessions" on public.session_members
    for insert with check (true);

create policy "Users can update session members" on public.session_members
    for update using (true);

-- PRESENCE CHECKS POLICIES
create policy "Session members can view presence checks" on public.presence_checks
    for select using (true);

create policy "Users can create presence checks" on public.presence_checks
    for insert with check (true);

-- PRESENCE VERIFICATIONS POLICIES
create policy "Session members can view presence verifications" on public.presence_verifications
    for select using (true);

create policy "Users can insert presence verifications" on public.presence_verifications
    for insert with check (true);

-- PRESENCE EVENTS POLICIES
create policy "Session participants can read events" on public.presence_events
    for select using (true);

create policy "System and participants can insert events" on public.presence_events
    for insert with check (true);

-- ==============================================================================
-- REALTIME REPLICATION ENABLEMENT
-- ==============================================================================
alter publication supabase_realtime add table public.sessions;
alter publication supabase_realtime add table public.session_members;
alter publication supabase_realtime add table public.presence_checks;
alter publication supabase_realtime add table public.presence_events;

-- ==============================================================================
-- HELPER FUNCTIONS & TRIGGERS
-- ==============================================================================

-- Auto-update session status when past end_time
create or replace function public.check_session_expiration()
returns trigger as $$
begin
    if NEW.end_time < now() and NEW.status = 'active' then
        NEW.status := 'completed';
    end if;
    return NEW;
end;
$$ language plpgsql;

create trigger tr_session_expiration
    before insert or update on public.sessions
    for each row
    execute function public.check_session_expiration();

-- ==============================================================================
-- UNIVERSAL BACKEND BLUETOOTH PROXIMITY PRESENCE VERIFICATION RPC
-- ==============================================================================
-- Enforces that presence CANNOT be recorded simply by joining or opening the session.
-- Requires active non-expired session, valid ephemeral token, member enrollment, and valid proximity proof.
create or replace function public.record_bluetooth_presence(
    p_session_id uuid,
    p_check_id uuid,
    p_user_id uuid,
    p_token text,
    p_method text default 'ble',
    p_rssi integer default null,
    p_metadata jsonb default '{}'::jsonb
)
returns jsonb as $$
declare
    v_is_enrolled boolean;
    v_check record;
    v_verification_id uuid;
begin
    -- 1. Validate that member is enrolled in the session
    select exists (
        select 1 from public.session_members
        where session_id = p_session_id and user_id = p_user_id
    ) into v_is_enrolled;

    if not v_is_enrolled then
        return jsonb_build_object(
            'success', false,
            'error', 'Member is not enrolled in this group session.'
        );
    end if;

    -- 2. Validate that active presence check exists and is not expired
    select * from public.presence_checks
    where id = p_check_id
      and session_id = p_session_id
      and status = 'active'
      and expires_at > timezone('utc'::text, now())
    into v_check;

    if v_check.id is null then
        return jsonb_build_object(
            'success', false,
            'error', 'Presence check session does not exist or has expired.'
        );
    end if;

    -- 3. Validate matching ephemeral check token
    if v_check.check_token <> p_token then
        return jsonb_build_object(
            'success', false,
            'error', 'Invalid presence verification token.'
        );
    end if;

    -- 4. Record cryptographic presence verification (idempotent upsert to prevent duplicates)
    insert into public.presence_verifications (
        check_id,
        session_id,
        user_id,
        verification_token_hash,
        verification_method,
        verified_at,
        rssi,
        metadata
    ) values (
        p_check_id,
        p_session_id,
        p_user_id,
        md5(p_check_id::text || ':' || p_user_id::text || ':' || p_token),
        coalesce(p_method, 'ble'),
        timezone('utc'::text, now()),
        p_rssi,
        p_metadata
    )
    on conflict (check_id, user_id) do update
    set verified_at = timezone('utc'::text, now()),
        rssi = coalesce(p_rssi, public.presence_verifications.rssi)
    returning id into v_verification_id;

    -- 5. Update session member status to present ONLY after validation
    update public.session_members
    set status = 'present',
        last_verified_at = timezone('utc'::text, now())
    where session_id = p_session_id and user_id = p_user_id;

    -- 6. Record audit event
    insert into public.presence_events (
        session_id,
        user_id,
        event_type,
        created_at,
        metadata
    ) values (
        p_session_id,
        p_user_id,
        'verified_ble',
        timezone('utc'::text, now()),
        jsonb_build_object('rssi', p_rssi, 'method', p_method, 'verification_id', v_verification_id)
    );

    return jsonb_build_object(
        'success', true,
        'verification_id', v_verification_id,
        'verified_at', timezone('utc'::text, now())
    );
end;
$$ language plpgsql security definer;

-- Backward compatibility alias
create or replace function public.record_bluetooth_attendance(
    p_session_id uuid,
    p_check_id uuid,
    p_user_id uuid,
    p_token text,
    p_method text default 'ble',
    p_rssi integer default null,
    p_metadata jsonb default '{}'::jsonb
)
returns jsonb as $$
begin
    return public.record_bluetooth_presence(
        p_session_id,
        p_check_id,
        p_user_id,
        p_token,
        p_method,
        p_rssi,
        p_metadata
    );
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- UNIVERSAL JOIN SESSION BY CODE RPC
-- ==============================================================================
create or replace function public.join_session_by_code(
    p_join_code text,
    p_user_id uuid,
    p_user_name text default 'Member',
    p_user_email text default null,
    p_user_phone text default null
)
returns jsonb as $$
declare
    v_clean_code text;
    v_session record;
    v_member record;
    v_auth_uid uuid;
begin
    -- 1. Normalize code (trim, uppercase, strip URL / prefix)
    v_clean_code := upper(trim(p_join_code));
    if v_clean_code like '%/JOIN/%' then
        v_clean_code := split_part(split_part(v_clean_code, '/JOIN/', 2), '?', 1);
    end if;
    v_clean_code := replace(v_clean_code, ' ', '');
    if length(v_clean_code) = 6 and v_clean_code ~ '^\d+$' then
        v_clean_code := 'HN-' || v_clean_code;
    elsif v_clean_code ~ '^HN\d{6}$' then
        v_clean_code := 'HN-' || substr(v_clean_code, 3);
    end if;

    -- 2. Ensure user exists in public.users to satisfy foreign key constraints
    v_auth_uid := auth.uid();
    insert into public.users (id, auth_id, name, email, phone)
    values (p_user_id, coalesce(v_auth_uid, p_user_id), coalesce(p_user_name, 'Member'), p_user_email, p_user_phone)
    on conflict (id) do update
    set name = coalesce(excluded.name, public.users.name),
        email = coalesce(excluded.email, public.users.email),
        phone = coalesce(excluded.phone, public.users.phone);

    -- 3. Lookup session by join_code or ID
    select * from public.sessions
    where upper(trim(join_code)) = v_clean_code
       or id::text = p_join_code
    into v_session;

    if v_session.id is null then
        return jsonb_build_object(
            'success', false,
            'error_code', 'NOT_FOUND',
            'error', 'Session not found. Please check your join code.'
        );
    end if;

    -- 4. Check status & expiration
    if v_session.status = 'completed' or v_session.end_time < timezone('utc'::text, now()) then
        return jsonb_build_object(
            'success', false,
            'error_code', 'EXPIRED',
            'error', 'This session has already expired.',
            'session', row_to_json(v_session)
        );
    end if;

    -- 5. Enroll member (Status is initial missing/unverified; does not mark present)
    insert into public.session_members (
        session_id,
        user_id,
        role,
        status,
        joined_at
    ) values (
        v_session.id,
        p_user_id,
        'member',
        'missing',
        timezone('utc'::text, now())
    )
    on conflict (session_id, user_id) do update
    set role = coalesce(public.session_members.role, 'member')
    returning * into v_member;

    -- 6. Audit event
    insert into public.presence_events (
        session_id,
        user_id,
        event_type,
        created_at,
        metadata
    ) values (
        v_session.id,
        p_user_id,
        'joined',
        timezone('utc'::text, now()),
        jsonb_build_object('name', p_user_name, 'join_code', v_clean_code)
    );

    return jsonb_build_object(
        'success', true,
        'session', row_to_json(v_session),
        'member', row_to_json(v_member)
    );
end;
$$ language plpgsql security definer;

-- Grants
grant execute on function public.join_session_by_code(text, uuid, text, text, text) to anon, authenticated, service_role;
grant execute on function public.record_bluetooth_presence(uuid, uuid, uuid, text, text, integer, jsonb) to anon, authenticated, service_role;
grant execute on function public.record_bluetooth_attendance(uuid, uuid, uuid, text, text, integer, jsonb) to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
