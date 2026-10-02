-- ==============================================================================
-- Fix for PostgreSQL Infinite Recursion in Row Level Security (RLS) Policies
-- Run this in your Supabase Dashboard -> SQL Editor -> Run
-- ==============================================================================

-- 1. DROP RECURSIVE SESSIONS POLICIES
drop policy if exists "Anyone can view session by join code or membership" on public.sessions;
drop policy if exists "Organizers can create sessions" on public.sessions;
drop policy if exists "Only organizers can update their sessions" on public.sessions;
drop policy if exists "Anyone can view active sessions or own sessions" on public.sessions;
drop policy if exists "Users can view sessions" on public.sessions;
drop policy if exists "Users can create sessions" on public.sessions;
drop policy if exists "Users can update sessions" on public.sessions;

-- 2. DROP RECURSIVE SESSION_MEMBERS POLICIES
drop policy if exists "Members can view other members in the same session" on public.session_members;
drop policy if exists "Users can join sessions" on public.session_members;
drop policy if exists "Organizers or users themselves can update membership status" on public.session_members;
drop policy if exists "Anyone authenticated can view session members" on public.session_members;
drop policy if exists "Users can view session members" on public.session_members;
drop policy if exists "Users or organizers can update session members" on public.session_members;

-- 3. DROP PRESENCE_CHECKS RECURSIVE POLICIES
drop policy if exists "Session members can view presence checks" on public.presence_checks;
drop policy if exists "Only organizers can initiate presence checks" on public.presence_checks;
drop policy if exists "Users can view presence checks" on public.presence_checks;
drop policy if exists "Users can create presence checks" on public.presence_checks;

-- 4. DROP PRESENCE_VERIFICATIONS POLICIES
drop policy if exists "Users can view presence verifications" on public.presence_verifications;
drop policy if exists "Users can create presence verifications" on public.presence_verifications;

-- ==============================================================================
-- RE-CREATE CLEAN, NON-RECURSIVE POLICIES
-- ==============================================================================

-- Sessions: Anyone authenticated or anonymous can view sessions by code / id
create policy "Users can view sessions" on public.sessions
    for select using (true);

create policy "Users can create sessions" on public.sessions
    for insert with check (true);

create policy "Users can update sessions" on public.sessions
    for update using (true);

-- Session Members: No self-referential subqueries (prevents infinite recursion error 42P17)
create policy "Users can view session members" on public.session_members
    for select using (true);

create policy "Users can join sessions" on public.session_members
    for insert with check (true);

create policy "Users can update session members" on public.session_members
    for update using (true);

-- Presence Checks: Ephemeral presence verification tokens
create policy "Users can view presence checks" on public.presence_checks
    for select using (true);

create policy "Users can create presence checks" on public.presence_checks
    for insert with check (true);

create policy "Users can update presence checks" on public.presence_checks
    for update using (true);

-- Presence Verifications: Audit proofs
create policy "Users can view presence verifications" on public.presence_verifications
    for select using (true);

create policy "Users can create presence verifications" on public.presence_verifications
    for insert with check (true);

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

-- Table and Function Grants
grant execute on function public.join_session_by_code(text, uuid, text, text, text) to anon, authenticated, service_role;
grant execute on function public.record_bluetooth_presence(uuid, uuid, uuid, text, text, integer, jsonb) to anon, authenticated, service_role;
grant execute on function public.record_bluetooth_attendance(uuid, uuid, uuid, text, text, integer, jsonb) to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
