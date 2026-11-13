create extension if not exists pgcrypto;

create table public.participants (
  id uuid primary key default gen_random_uuid(),
  username text not null unique check (username in ('marc', 'ernest', 'carla', 'noe')),
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
select 'noe', 'Noe', id from auth.users where email = 'noe@amigo-invisible.test';

do $$
begin
  if (select count(*) from public.participants) <> 4 then
    raise exception 'Se necesitan exactamente los cuatro usuarios de Auth: Marc, Ernest, Carla y Noe.';
  end if;

  if exists (select 1 from public.participants where recipient_id is not null) then
    raise exception 'Ya existe un sorteo. No vuelvas a ejecutar el bloque de sorteo.';
  end if;
end
$$;

with shuffled as (
  select
    id,
    row_number() over (order by random()) as position,
    count(*) over () as total
  from public.participants
),
draw as (
  select giver.id, receiver.id as recipient_id
  from shuffled as giver
  join shuffled as receiver
    on receiver.position = case
      when giver.position = giver.total then 1
      else giver.position + 1
    end
)
update public.participants as participant
set recipient_id = draw.recipient_id
from draw
where participant.id = draw.id;
