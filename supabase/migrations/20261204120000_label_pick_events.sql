-- A label read is kept with what came of it, so the label search can be
-- checked against what readers actually meant: the likeliest bottle now
-- carries the words read off the label, and a new 'label_pick' row holds
-- the bottle the reader chose from a label's candidates with those words.
-- The photo itself still never leaves the phone. A label_match sent by an
-- older app without the words stays valid.
set local lock_timeout = '5s';

alter table public.drink_discovery_events
  drop constraint drink_discovery_events_kind_check,
  add constraint drink_discovery_events_kind_check check (kind = any (array[
    'search_pick', 'search_empty', 'label_match', 'label_miss', 'label_pick',
    'fit_view'
  ])),
  drop constraint drink_discovery_events_query_shape,
  add constraint drink_discovery_events_query_shape check (case kind
    when 'search_empty' then query_text is not null
    when 'label_miss' then query_text is not null
    when 'label_pick' then query_text is not null and alcohol_item_id is not null
    when 'search_pick' then true
    when 'label_match' then true
    else query_text is null
  end);
