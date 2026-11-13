create extension if not exists pgcrypto;

create table public.participants (
  id uuid primary key default gen_random_uuid(),
  username text not null unique check (
    username in ('marc', 'ernest', 'carla', 'noe', 'jonay', 'oriol', 'ivan', 'nikola', 'aoxin', 'cai')
  ),
  name text not null,
  auth_user_id uuid not null unique references auth.users (id) on delete cascade,
  recipient_id uuid unique references public.participants (id),
  constraint recipient_is_not_self check (recipient_id is null or recipient_id <> id)
);

create table public.wishlist_items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.participants (id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 240),
  created_at timestamptz not null default now()
);

alter table public.participants enable row level security;
alter table public.wishlist_items enable row level security;

grant select on public.participants to authenticated;
grant select, insert, delete on public.wishlist_items to authenticated;

create policy "Participants can read their own profile"
  on public.participants for select to authenticated
  using (auth_user_id = (select auth.uid()));

create policy "Participants can read their own and recipient's wishes"
  on public.wishlist_items for select to authenticated
  using (
    owner_id = (
      select id from public.participants where auth_user_id = (select auth.uid())
    )
    or owner_id = (
      select recipient_id from public.participants where auth_user_id = (select auth.uid())
    )
  );

create policy "Participants can add wishes to their own list"
  on public.wishlist_items for insert to authenticated
  with check (
    owner_id = (
      select id from public.participants where auth_user_id = (select auth.uid())
    )
  );

create policy "Participants can delete wishes from their own list"
  on public.wishlist_items for delete to authenticated
  using (
    owner_id = (
      select id from public.participants where auth_user_id = (select auth.uid())
    )
  );

create function public.get_my_draw()
returns table (my_id uuid, my_name text, recipient_id uuid, recipient_name text)
language sql
stable
security definer
set search_path = public
as $$
  select me.id, me.name, me.recipient_id, recipient.name
  from public.participants as me
  left join public.participants as recipient on recipient.id = me.recipient_id
  where me.auth_user_id = (select auth.uid());
$$;

revoke all on function public.get_my_draw() from public, anon;
grant execute on function public.get_my_draw() to authenticated;

insert into public.participants (username, name, auth_user_id)
select 'marc', 'Marc', id from auth.users where email = 'marc@amigo-invisible.test'
union all
select 'ernest', 'Ernest', id from auth.users where email = 'ernest@amigo-invisible.test'
union all
select 'carla', 'Carla', id from auth.users where email = 'carla@amigo-invisible.test'
union all
select 'noe', 'Noe', id from auth.users where email = 'noe@amigo-invisible.test'
union all
select 'jonay', 'Jonay', id from auth.users where email = 'jonay@amigo-invisible.test'
union all
select 'oriol', 'Oriol', id from auth.users where email = 'oriol@amigo-invisible.test'
union all
select 'ivan', 'Ivan', id from auth.users where email = 'ivan@amigo-invisible.test'
union all
select 'nikola', 'Nikola', id from auth.users where email = 'nikola@amigo-invisible.test'
union all
select 'aoxin', 'Aoxin', id from auth.users where email = 'aoxin@amigo-invisible.test'
union all
select 'cai', 'Cai', id from auth.users where email = 'cai@amigo-invisible.test';

do $$
begin
  if (select count(*) from public.participants) <> 10 then
    raise exception 'Se necesitan exactamente los diez usuarios de Auth antes de hacer el sorteo.';
  end if;

  if exists (select 1 from public.participants where recipient_id is not null) then
    raise exception 'Ya existe un sorteo. No vuelvas a ejecutar el bloque de sorteo.';
  end if;
end
$$;

with recursive
participants_by_name as (
  select id, username
  from public.participants
),
ordered_people as (
  select array_agg(id order by username) as giver_ids
  from participants_by_name
),
permutations(giver_ids, recipient_ids, next_index) as (
  select giver_ids, array[]::uuid[], 1
  from ordered_people

  union all

  select
    permutations.giver_ids,
    array_append(permutations.recipient_ids, candidate.id),
    permutations.next_index + 1
  from permutations
  join participants_by_name as giver
    on giver.id = permutations.giver_ids[permutations.next_index]
  cross join participants_by_name as candidate
  where permutations.next_index <= cardinality(permutations.giver_ids)
    and candidate.id <> giver.id
    and (giver.username <> 'marc' or candidate.username = 'noe')
    and not (
      (giver.username = 'marc' and candidate.username = 'carla')
      or (giver.username = 'carla' and candidate.username = 'marc')
      or (giver.username = 'ernest' and candidate.username = 'noe')
      or (giver.username = 'noe' and candidate.username = 'ernest')
      or (giver.username = 'ivan' and candidate.username = 'nikola')
      or (giver.username = 'nikola' and candidate.username = 'ivan')
      or (giver.username = 'aoxin' and candidate.username = 'cai')
      or (giver.username = 'cai' and candidate.username = 'aoxin')
    )
    and not (candidate.id = any(permutations.recipient_ids))
),
selected_draw as (
  select giver_ids, recipient_ids
  from permutations
  where next_index = cardinality(giver_ids) + 1
  order by random()
  limit 1
),
draw as (
  select assignment.giver_id, assignment.recipient_id
  from selected_draw
  cross join lateral unnest(giver_ids, recipient_ids)
    as assignment(giver_id, recipient_id)
)
update public.participants as participant
set recipient_id = draw.recipient_id
from draw
where participant.id = draw.giver_id;

do $$
begin
  if exists (
    select 1
    from public.participants
    where recipient_id is null or recipient_id = id
  ) or (select count(distinct recipient_id) from public.participants) <> 10
    or not exists (
      select 1
      from public.participants as marc
      join public.participants as noe on noe.username = 'noe'
      where marc.username = 'marc' and marc.recipient_id = noe.id
    )
    or exists (
      select 1
      from public.participants as giver
      join public.participants as recipient on recipient.id = giver.recipient_id
      where (giver.username = 'marc' and recipient.username = 'carla')
        or (giver.username = 'carla' and recipient.username = 'marc')
        or (giver.username = 'ernest' and recipient.username = 'noe')
        or (giver.username = 'noe' and recipient.username = 'ernest')
        or (giver.username = 'ivan' and recipient.username = 'nikola')
        or (giver.username = 'nikola' and recipient.username = 'ivan')
        or (giver.username = 'aoxin' and recipient.username = 'cai')
        or (giver.username = 'cai' and recipient.username = 'aoxin')
    ) then
    raise exception 'El sorteo no ha respetado las restricciones configuradas.';
  end if;
end
$$;
