import { parseCreateTasteCardResultRequest } from "../_shared/taste_card/service/serialization.ts";
import { ACTUAL_REQUESTS_V3 } from "./fixtures/actual_questionnaire_v3.ts";

function requestWithIdentification(identification: Record<string, unknown>) {
  const request: Record<string, unknown> = structuredClone(
    ACTUAL_REQUESTS_V3[0].request,
  );
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
