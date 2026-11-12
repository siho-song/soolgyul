// Checks shared by the tests that compare what goes over the wire or comes
// out of the database: two values are the same when their JSON is.

export function assert(
  value: unknown,
  message = "assertion failed",
): asserts value {
  if (!value) throw new Error(message);
}

export function same(actual: unknown, expected: unknown, label = "value") {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${label}: expected ${b}, received ${a}`);
}

/** Passes when `work` fails with a message that holds `fragment`. */
export async function rejects(
  work: () => Promise<unknown>,
  fragment: string,
  label = "call",
) {
  try {
    await work();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes(fragment)) {
      throw new Error(
        `${label}: expected "${fragment}", received "${message}"`,
      );
    }
    return;
  }
  throw new Error(`${label}: expected rejection "${fragment}"`);
}

/** Passes when `fn` fails with an error whose `code` is `code`. */
export function assertRejects(
  fn: () => unknown | Promise<unknown>,
  code: string,
): Promise<void> {
  return Promise.resolve()
    .then(fn)
    .then(
      () => {
        throw new Error(`Expected rejection ${code}`);
      },
      (error) => {
        if (error?.code !== code) {
          throw new Error(
            `Expected rejection ${code}, received ${error?.code ?? error}`,
          );
        }
      },
    );
}
