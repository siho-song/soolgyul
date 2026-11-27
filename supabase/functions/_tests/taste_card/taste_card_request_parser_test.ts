import { parseCreateTasteCardResultRequest } from "../../_shared/taste_card/service/serialization.ts";
import flutterWire from "../fixtures/sensory_flutter_wire_v2.json" with {
  type: "json",
};

function requestWithIdentification(identification: Record<string, unknown>) {
  const request: Record<string, unknown> = structuredClone(flutterWire);
  request.alcohol_identification = identification;
  return request;
}

function rejectionCode(request: Record<string, unknown>): string | undefined {
  try {
    parseCreateTasteCardResultRequest(request);
  } catch (error) {
    return (error as { code?: string }).code;
  }
  return undefined;
}

function expectCode(actual: string | undefined, expected: string) {
  if (actual !== expected) {
    throw new Error(`expected ${expected}, received ${actual}`);
  }
}

Deno.test("catalog matches must carry a UUID item id before any attempt exists", () => {
  const catalogMatch = (alcoholItemId: unknown) =>
    requestWithIdentification({
      mode: "catalog_match",
      alcohol_item_id: alcoholItemId,
      alcohol_name_snapshot: "테스트 와인",
      category: "wine",
    });
  const parsed = parseCreateTasteCardResultRequest(
    catalogMatch("20000000-0000-4000-8000-000000000001"),
  );
  if (
    parsed.alcohol_identification.alcohol_item_id !==
      "20000000-0000-4000-8000-000000000001"
  ) {
    throw new Error("catalog match lost");
  }
  expectCode(rejectionCode(catalogMatch("alcohol-item-1")), "uuid_required");
  expectCode(rejectionCode(catalogMatch(null)), "string_required");
});

Deno.test("a drink entered by name is refused: the old mode and the old key fail closed", () => {
  expectCode(
    rejectionCode(requestWithIdentification({
      mode: "direct_input",
      alcohol_item_id: null,
      alcohol_name_snapshot: "직접 입력 술",
      category: null,
    })),
    "direct_input_removed",
  );
  expectCode(
    rejectionCode(requestWithIdentification({
      mode: "catalog_match",
      alcohol_item_id: "20000000-0000-4000-8000-000000000001",
      entered_alcohol_name: null,
      alcohol_name_snapshot: "테스트 와인",
      category: "wine",
    })),
    "entered_alcohol_name_removed",
  );
});

Deno.test("the look chosen with the answers may come with the request, as option keys by the note's field", () => {
  const withLook = (look: unknown) => ({
    ...structuredClone(flutterWire) as Record<string, unknown>,
    look,
  });
  const look = (value: unknown) =>
    parseCreateTasteCardResultRequest(withLook(value)).look;
  const same = (actual: unknown, expected: unknown) => {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      throw new Error(`${JSON.stringify(actual)}`);
    }
  };
  same(look({ appearance: "garnet", appearance_texture: "medium" }), {
    appearance: "garnet",
    appearance_texture: "medium",
  });
  same(look({ appearance_texture: "milky" }), { appearance_texture: "milky" });
  same(look({}), {});
  // An app that sends none sends the request it always did.
  const plain = parseCreateTasteCardResultRequest(structuredClone(flutterWire));
  if ("look" in plain) throw new Error("a look appeared from nowhere");
  // Nothing but the two fields, and nothing but an option key in them.
  expectCode(rejectionCode(withLook(null)), "object_required");
  expectCode(
    rejectionCode(withLook({ appearance: "garnet", serving: "neat" })),
    "wire_keys_mismatch",
  );
  expectCode(rejectionCode(withLook({ appearance: 3 })), "string_required");
  expectCode(
    rejectionCode(withLook({ appearance: "Garnet; drop table" })),
    "look_option_invalid",
  );
  expectCode(
    rejectionCode(withLook({ appearance_texture: "a".repeat(41) })),
    "look_option_invalid",
  );
});
