-- The record card no longer takes a photo: the app keeps only the one-line
-- note, so the photo path column and the owner RPC that set it go. No record
-- ever stored a photo. The soolgyul-private bucket stays for inquiry
-- attachments.

drop function if exists public.soolgyul_set_my_drink_record_photo(uuid, text);
alter table public.drink_records drop column if exists photo_storage_path;
