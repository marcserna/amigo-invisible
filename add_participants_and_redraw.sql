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
    where migration_key = 'add-five-participants-and-redraw-v1'
  ) then
    raise exception 'Esta migración ya se ejecutó. No la vuelvas a ejecutar.';
  end if;
end
$$;

alter table public.participants
  drop constraint if exists participants_username_check;

alter table public.participants
  add constraint participants_username_check
  check (username in ('marc', 'ernest', 'carla', 'noe', 'jonay', 'oriol', 'ivan', 'nikola', 'aoxin'));

with expected_users(username, name, email) as (
  values
    ('marc', 'Marc', 'marc@amigo-invisible.test'),
    ('ernest', 'Ernest', 'ernest@amigo-invisible.test'),
    ('carla', 'Carla', 'carla@amigo-invisible.test'),
    ('noe', 'Noe', 'noe@amigo-invisible.test'),
    ('jonay', 'Jonay', 'jonay@amigo-invisible.test'),
    ('oriol', 'Oriol', 'oriol@amigo-invisible.test'),
    ('ivan', 'Ivan', 'ivan@amigo-invisible.test'),
    ('nikola', 'Nikola', 'nikola@amigo-invisible.test'),
    ('aoxin', 'Aoxin', 'aoxin@amigo-invisible.test')
)
insert into public.participants (username, name, auth_user_id)
select expected.username, expected.name, users.id
from expected_users as expected
join auth.users as users on users.email = expected.email
where not exists (
  select 1
  from public.participants as participant
  where participant.username = expected.username
);

do $$
begin
  if (select count(*) from public.participants) <> 9 then
    raise exception 'Deben existir exactamente nueve participantes. Comprueba que has creado las cinco cuentas nuevas.';
  end if;

  if exists (
    with expected_users(username, email) as (
      values
        ('marc', 'marc@amigo-invisible.test'),
        ('ernest', 'ernest@amigo-invisible.test'),
        ('carla', 'carla@amigo-invisible.test'),
        ('noe', 'noe@amigo-invisible.test'),
        ('jonay', 'jonay@amigo-invisible.test'),
        ('oriol', 'oriol@amigo-invisible.test'),
        ('ivan', 'ivan@amigo-invisible.test'),
        ('nikola', 'nikola@amigo-invisible.test'),
        ('aoxin', 'aoxin@amigo-invisible.test')
    )
    select 1
    from expected_users as expected
    left join auth.users as users on users.email = expected.email
    left join public.participants as participant
      on participant.username = expected.username
      and participant.auth_user_id = users.id
    where participant.id is null
  ) then
    raise exception 'Falta una cuenta de acceso o no coincide con su participante. No se ha cambiado el sorteo.';
  end if;
end
$$;

update public.participants
set recipient_id = null;

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

do $$
begin
  if exists (
    select 1
    from public.participants
    where recipient_id is null or recipient_id = id
  ) or (select count(distinct recipient_id) from public.participants) <> 9 then
    raise exception 'El sorteo no ha asignado correctamente a los nueve participantes.';
  end if;
end
$$;

insert into public.draw_migrations (migration_key)
values ('add-five-participants-and-redraw-v1');

commit;
