begin;

do $$
begin
  if (select count(*) from public.participants) <> 10 then
    raise exception 'Se necesitan exactamente diez participantes. Ejecuta primero la migración para añadir a Cai.';
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
        ('aoxin'),
        ('cai')
    )
    select 1
    from expected_users as expected
    left join public.participants as participant using (username)
    where participant.id is null
  ) then
    raise exception 'Falta uno o más de los diez participantes esperados.';
  end if;
end
$$;

update public.participants
set recipient_id = null;

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
    raise exception 'El sorteo no ha asignado correctamente a los diez participantes.';
  end if;
end
$$;

commit;
