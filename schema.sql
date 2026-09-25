-- Supabase SQL Editor で一括実行

create table quiz_state (
  id smallint primary key default 1,
  current_round int not null default 1,
  check (id = 1)
);

create table rounds (
  round int primary key,
  next_order int not null default 0,
  button_on boolean not null default false,
  button_enabled_at timestamptz
);

create table participants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  joined_at timestamptz not null default now()
);

create table presses (
  round int not null references rounds(round),
  participant_id uuid not null references participants(id),
  name text not null,
  order_num int not null,
  elapsed_ms int not null,
  pressed_at timestamptz not null default now(),
  primary key (round, participant_id)
);

insert into quiz_state (id, current_round) values (1, 1);
insert into rounds (round, next_order, button_on) values (1, 0, false);

-- 押下を原子的に処理するRPC。presses への直接INSERT権限は与えず、これ経由のみに限定する。
create or replace function press_buzzer(p_round int, p_participant_id uuid, p_name text)
returns table(out_order int, out_elapsed_ms int)
language plpgsql
security definer
as $$
declare
  v_enabled_at timestamptz;
  v_button_on boolean;
  v_order int;
  v_elapsed int;
begin
  select button_on, button_enabled_at into v_button_on, v_enabled_at
  from rounds where round = p_round for update;

  if v_button_on is not true then
    raise exception 'button_not_active';
  end if;

  update rounds set next_order = next_order + 1 where round = p_round
    returning next_order into v_order;

  v_elapsed := greatest(0, extract(epoch from (now() - v_enabled_at)) * 1000)::int;

  begin
    insert into presses(round, participant_id, name, order_num, elapsed_ms)
    values (p_round, p_participant_id, p_name, v_order, v_elapsed);
  exception when unique_violation then
    raise exception 'already_pressed';
  end;

  return query select v_order, v_elapsed;
end;
$$;

-- 「次の問題へ」をまとめて処理するRPC（ラウンド繰り上げ + 新ラウンド行作成）
create or replace function advance_round()
returns int
language plpgsql
security definer
as $$
declare
  v_new_round int;
begin
  update quiz_state set current_round = current_round + 1
    where id = 1 returning current_round into v_new_round;
  insert into rounds(round, next_order, button_on) values (v_new_round, 0, false);
  return v_new_round;
end;
$$;

-- 全リセット用RPC
create or replace function reset_all()
returns void
language plpgsql
security definer
as $$
begin
  delete from presses;
  delete from participants;
  delete from rounds;
  update quiz_state set current_round = 1 where id = 1;
  insert into rounds(round, next_order, button_on) values (1, 0, false);
end;
$$;

-- Row Level Security
alter table quiz_state enable row level security;
alter table rounds enable row level security;
alter table participants enable row level security;
alter table presses enable row level security;

create policy "anon read quiz_state" on quiz_state for select to anon using (true);
create policy "anon read rounds" on rounds for select to anon using (true);
create policy "anon update rounds" on rounds for update to anon using (true);
create policy "anon read participants" on participants for select to anon using (true);
create policy "anon insert participants" on participants for insert to anon with check (true);
create policy "anon read presses" on presses for select to anon using (true);
-- presses への insert/delete ポリシーは意図的に作らない（RPC経由のみ許可）

grant execute on function press_buzzer(int, uuid, text) to anon;
grant execute on function advance_round() to anon;
grant execute on function reset_all() to anon;

-- Realtime配信対象に追加
alter publication supabase_realtime add table rounds, participants, presses, quiz_state;
