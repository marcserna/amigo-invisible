begin;

do $$
begin
  if (select count(*) from public.participants) <> 9 then
    raise exception 'Se necesitan exactamente nueve participantes. Ejecuta primero la migración para añadirlos.';
  end if;

  if exists (
    with expected_users(username) as (
      values
        ('marc'),
        ('ernest'),
        ('carla'),
        ('noe'),
        ('jonay'),
        ('oriol'),
        ('ivan'),
        ('nikola'),
        ('aoxin')
    )
    select 1
    from expected_users as expected
    left join public.participants as participant using (username)
    where participant.id is null
  ) then
    raise exception 'Falta uno o más de los nueve participantes esperados.';
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

commit;
