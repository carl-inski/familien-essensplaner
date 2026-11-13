-- Serverzeit in Millisekunden. Handys gleichen damit ihre Uhr ab, damit beim
-- Tauziehen alle in derselben Sekunde starten (lib/decide.ts zugTimeline).
-- clock_timestamp statt now(): now() ist der Beginn der Transaktion.

create or replace function public.ep_server_now()
returns double precision
language sql volatile set search_path = ''
as $$ select extract(epoch from clock_timestamp()) * 1000 $$;

revoke execute on function public.ep_server_now() from public, anon;
grant execute on function public.ep_server_now() to authenticated;
