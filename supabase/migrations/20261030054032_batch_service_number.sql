-- MAIN-112: a multi-vehicle invoice gets a running number, shown as MVI-12 and used in
-- its link (/multi-vehicle-invoices/MVI-12), the way a job card has job_card_number.
-- Until now it was known only by its uuid; the vendor's invoice_no cannot stand in, as
-- vendors reuse numbers.
--
-- GENERATED ALWAYS AS IDENTITY, like job_cards.job_card_number: the prod→staging seed
-- skips such columns, so staging numbers its copies afresh rather than colliding.
-- Existing rows are numbered in creation order first; the identity then continues
-- after them.

alter table public.batch_services add column batch_number integer;

update public.batch_services b
set    batch_number = n.rn
from   (select id, row_number() over (order by created_at, id) as rn
        from public.batch_services) n
where  n.id = b.id;

alter table public.batch_services alter column batch_number set not null;

alter table public.batch_services
    alter column batch_number add generated always as identity;

select setval(pg_get_serial_sequence('public.batch_services', 'batch_number'),
              coalesce((select max(batch_number) from public.batch_services), 0) + 1,
              false);

alter table public.batch_services
    add constraint batch_services_batch_number_key unique (batch_number);
