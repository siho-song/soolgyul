import { createSupabaseLikeDatabase } from "./helpers/pglite_supabase.ts";

// A session's start and each change of its IP address leave a sign-in
// record; no client reads the records.

const MEMBER = "a0000000-0000-4000-8000-000000000061";

Deno.test("a session start and an address change are recorded", async () => {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data) values
      ('${MEMBER}', 'member@example.test', '{"provider":"google"}');
    insert into auth.sessions (id, user_id, ip, user_agent) values
      ('c0000000-0000-4000-8000-000000000001', '${MEMBER}', '203.0.113.7', 'app');
    update auth.sessions set user_agent = 'app 2';
    update auth.sessions set ip = '203.0.113.7';
    update auth.sessions set ip = '198.51.100.9';
    insert into auth.sessions (user_id) values ('${MEMBER}');
  `);
  const { rows } = await db.query<{ ip: string; user_agent: string }>(
    "select host(ip) ip, user_agent from public.sign_in_records order by id",
  );
  const seen = rows.map((row) => `${row.ip} ${row.user_agent}`);
  const expected = ["203.0.113.7 app", "198.51.100.9 app 2"];
  if (JSON.stringify(seen) !== JSON.stringify(expected)) {
    throw new Error(`records, got ${seen}`);
  }

  await db.exec("set role authenticated;");
  let refused = false;
  try {
    await db.query("select * from public.sign_in_records");
  } catch {
    refused = true;
  } finally {
    await db.exec("reset role;");
  }
  if (!refused) throw new Error("a client reads the sign-in records");

  const job = await db.query<{ command: string }>(
    "select command from cron.job where jobname = 'soolgyul-sign-in-records-retention'",
  );
  if (!job.rows[0]?.command.includes("public.sign_in_records")) {
    throw new Error("the retention job deletes old sign-in records");
  }
});
