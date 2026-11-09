-- Four alcohol_items columns nothing reads any more, decided 2026-10-27:
--   representative_volume_ml  a display aid never shown; a product is one
--                             row whatever the bottle size
--   edition_text, batch_text  711 and 299 scraps such as '에디션' that the
--                             product name already carries
--   product_group_id          grouped a wine with its vintages; its only reader
--                             was the borrowed-photo fallback that went with
--                             20261027100000_catalog_media_slim

alter table public.alcohol_items
  drop column representative_volume_ml,
  drop column edition_text,
  drop column batch_text,
  drop column product_group_id;
