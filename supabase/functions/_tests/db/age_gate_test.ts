import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asUser } from "../helpers/db_session.ts";
import { rejects, same } from "../helpers/assert.ts";

// Sign-up counts age and checks the birth date against today's date in
// Korea. The database runs in UTC, so between 00:00 and 09:00 KST its own
// date is still yesterday; on 1 January that is last year.

const ids = {
  turning19: "a0000000-0000-4000-8000-000000000061",
  turning18: "a0000000-0000-4000-8000-000000000062",
  bornToday: "a0000000-0000-4000-8000-000000000063",
};

Deno.test("sign-up age gate uses the Korean date", async () => {
  const db = await createSupabaseLikeDatabase();
  const realNow = Date.now;
  try {
    await db.exec(`
      set time zone 'UTC';
      insert into auth.users (id, email, raw_app_meta_data) values
        ('${ids.turning19}', 'a@example.test', '{"provider":"kakao"}'),
        ('${ids.turning18}', 'b@example.test', '{"provider":"kakao"}'),
        ('${ids.bornToday}', 'c@example.test', '{"provider":"kakao"}');
    `);
    const complete = (birthDate: string) =>
      db.query<{ result: { profile_complete: boolean } }>(
        `select public.soolgyul_complete_my_profile(
           gen_random_uuid(), '술결', $1::date, true, 'soolgyul-terms-v1',
           'soolgyul-privacy-v1', 'soolgyul-marketing-v1', true, true, false
         ) as result`,
        [birthDate],
      );

    // 03:00 on 1 January 2027 in Seoul is 18:00 on 31 December 2026 in UTC.
    // PGlite reads the clock from the host.
    Date.now = () => Date.parse("2027-01-01T03:00:00+09:00");
    same(
      (await db.query<{ day: string }>("select current_date::text as day"))
        .rows[0].day,
      "2026-12-31",
      "the database's own date is still last year",
    );

    await asUser(db, ids.turning19, async () => {
      same(
        (await complete("2008-12-31")).rows[0].result.profile_complete,
        true,
        "born in 2008, 19 in Korea's 2027",
      );
    });
    await asUser(db, ids.turning18, async () => {
      await rejects(
        () => complete("2009-01-01"),
        "age_gate_required",
        "born in 2009, 18 in 2027",
      );
    });
    await asUser(db, ids.bornToday, async () => {
      await rejects(
        () => complete("2027-01-02"),
        "birth_date_invalid",
        "tomorrow in Korea is in the future",
      );
      // Today in Korea is not a future date, though it is too young.
      await rejects(
        () => complete("2027-01-01"),
        "age_gate_required",
        "today in Korea is a valid birth date",
      );
    });
  } finally {
    Date.now = realNow;
    await db.close();
  }
});
