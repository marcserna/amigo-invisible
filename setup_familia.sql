begin;

create table if not exists public.draw_migrations (
  migration_key text primary key,
  completed_at timestamptz not null default now()
);

revoke all on public.draw_migrations from public, anon, authenticated;

do $$
begin
  if exists (
    select 1
    from public.draw_migrations
    where migration_key = 'create-family-draw-v1'
  ) then
    raise exception 'El sorteo de Familia ya está configurado. No vuelvas a ejecutar esta migración.';
  end if;

  if exists (
    with expected_users(username, email) as (
      values
        ('marc', 'marc@amigo-invisible.test'),
        ('andrea', 'andrea@amigo-invisible.test'),
        ('elena', 'elena@amigo-invisible.test'),
        ('iona', 'iona@amigo-invisible.test'),
        ('eva', 'eva@amigo-invisible.test'),
        ('ana', 'ana@amigo-invisible.test')
    )
    select 1
    from expected_users as expected
    left join auth.users as users on users.email = expected.email
    where users.id is null
  ) then
    raise exception 'Crea primero las seis cuentas de Familia en Supabase Auth con los emails indicados en README.md.';
  end if;
end
$$;

create table public.family_participants (
  id uuid primary key default gen_random_uuid(),
  username text not null unique check (
    username in ('marc', 'andrea', 'elena', 'iona', 'eva', 'ana')
  ),
  name text not null,
  auth_user_id uuid not null unique references auth.users (id) on delete cascade,
  recipient_id uuid unique references public.family_participants (id),
  constraint family_recipient_is_not_self check (recipient_id is null or recipient_id <> id)
);

create table public.family_wishlist_items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.family_participants (id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 240),
  created_at timestamptz not null default now()
);

alter table public.family_participants enable row level security;
alter table public.family_wishlist_items enable row level security;

grant select on public.family_participants to authenticated;
grant select, insert, delete on public.family_wishlist_items to authenticated;

create policy "Family participants can read their own profile"
  on public.family_participants for select to authenticated
  using (auth_user_id = (select auth.uid()));

create policy "Family participants can read their own and recipient's wishes"
  on public.family_wishlist_items for select to authenticated
  using (
    owner_id = (
      select id from public.family_participants where auth_user_id = (select auth.uid())
    )
    or owner_id = (
      select recipient_id from public.family_participants where auth_user_id = (select auth.uid())
    )
  );

create policy "Family participants can add wishes to their own list"
  on public.family_wishlist_items for insert to authenticated
  with check (
    owner_id = (
      select id from public.family_participants where auth_user_id = (select auth.uid())
    )
  );

create policy "Family participants can delete wishes from their own list"
  on public.family_wishlist_items for delete to authenticated
  using (
    owner_id = (
      select id from public.family_participants where auth_user_id = (select auth.uid())
    )
  );

create function public.get_my_family_draw()
returns table (my_id uuid, my_name text, recipient_id uuid, recipient_name text)
language sql
stable
security definer
set search_path = public
as $$
  select me.id, me.name, me.recipient_id, recipient.name
  from public.family_participants as me
  left join public.family_participants as recipient on recipient.id = me.recipient_id
  where me.auth_user_id = (select auth.uid());
$$;

revoke all on function public.get_my_family_draw() from public, anon;
grant execute on function public.get_my_family_draw() to authenticated;

insert into public.family_participants (username, name, auth_user_id)
select expected.username, expected.name, users.id
from (
  values
    ('marc', 'Marc', 'marc@amigo-invisible.test'),
    ('andrea', 'Andrea', 'andrea@amigo-invisible.test'),
    ('elena', 'Elena', 'elena@amigo-invisible.test'),
    ('iona', 'Iona', 'iona@amigo-invisible.test'),
    ('eva', 'Eva', 'eva@amigo-invisible.test'),
    ('ana', 'Ana', 'ana@amigo-invisible.test')
) as expected(username, name, email)
join auth.users as users on users.email = expected.email;

with recursive
participants_by_name as (
  select id, username
  from public.family_participants
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
update public.family_participants as participant
set recipient_id = draw.recipient_id
from draw
where participant.id = draw.giver_id;

do $$
begin
  if (select count(*) from public.family_participants) <> 6
    or exists (
      select 1
      from public.family_participants
      where recipient_id is null or recipient_id = id
    )
    or (select count(distinct recipient_id) from public.family_participants) <> 6 then
    raise exception 'El sorteo de Familia no ha asignado correctamente a las seis personas.';
  end if;
end
$$;

insert into public.draw_migrations (migration_key)
values ('create-family-draw-v1');

commit;
