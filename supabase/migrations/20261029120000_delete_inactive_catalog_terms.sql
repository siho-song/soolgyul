-- Catalog terms that were switched off (styles, ingredients, processes,
-- maturations, classifications and descriptors of removed categories, plus
-- values dropped from the registry) leave the table instead of staying as
-- inactive rows. No product, active term or reader uses them; the registry
-- seed now deletes removed values the same way, so the delete guard goes.
-- Term identity (type and key) stays immutable.
drop trigger catalog_terms_prevent_delete on public.catalog_terms;

delete from public.catalog_terms
where not is_active;
