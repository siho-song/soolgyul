// The two questions a label photo is put to the model with: which of the
// app's candidates the bottle is, and whether it is the product the
// catalog's own photo of one candidate shows.
import Anthropic from "npm:@anthropic-ai/sdk@1.14.0";
import type { LabelCandidate } from "./candidates.ts";

export type JudgeUsage = { input_tokens: number; output_tokens: number };

export type CandidatePick = {
  /** The place of the picked candidate, counted from one; 0 for none of them. */
  pick: number;
  /** Whether the model would stake its name on [pick]. */
  sure: boolean;
  usage: JudgeUsage;
};

export type CatalogPhotoMatch = {
  /** Whether the two photos show one product, and the model is sure of it. */
  same: boolean;
  usage: JudgeUsage;
};

export interface LabelJudge {
  /** Which of [candidates] the bottle in [photo] (a base64 JPEG) is. */
  pickCandidate(
    photo: string,
    candidates: readonly LabelCandidate[],
  ): Promise<CandidatePick>;

  /** Whether the bottle in [photo] is what the catalog's photo at [catalogPhotoUrl] of [candidate] shows. */
  matchCatalogPhoto(
    photo: string,
    candidate: LabelCandidate,
    catalogPhotoUrl: string,
  ): Promise<CatalogPhotoMatch>;
}

/** The model did not answer, or answered what cannot be read. */
export class LabelJudgeUnavailable extends Error {
  constructor(reason: string) {
    super(reason);
    this.name = "LabelJudgeUnavailable";
  }
}

const MODEL = "claude-haiku-5-5";

const PICK_INSTRUCTION =
  `You match one bottle to a drinks catalog. The message holds a photo of the bottle and up to ten \`candidates\` (\`n\`, then name | maker). The candidates were picked by a text reader that often misreads ornate letters. Read the label yourself, and use what you know about the product as well: its bottle shape, label design and colours can tell which product it is even when the name is not printed.

The right drink may be anywhere in the list, or not in the list at all: about half of these bottles are not in the catalog, and then the list holds only look-alikes (other wines of the same maker, same grape, same region).

- \`pick\`: the \`n\` of the candidate that is this very product: the same maker's same wine or bottling (ignore the vintage year; spelling, transliteration or an owner's name in front of the catalog name may differ). \`0\` when none of the candidates is this product. A sibling is NOT the product: another grape, another cuvée or range, another colour, another age statement of the same maker is \`0\`.
- \`sure\`: true only when you would stake your name on the pick being exactly this product; false when it is your best guess. For \`pick\` 0, true means you are confident none of the candidates is it.
- Before \`sure\` is true, check the candidate against the label word by word. The maker must be the same: the same wine name from another maker is not the product. Every word that sets the candidate apart from its siblings (cuvée, vineyard, grape, colour, a classification such as 1er Cru, an age) must be on the label, and the label must not carry such a word the candidate lacks: a vineyard, cuvée or classification printed on the label but missing from the candidate's name means a sibling, so \`pick\` is 0. When the label does not show the candidate's grape or cuvée at all, \`sure\` is false.
- \`read\`: the main words on the front label as printed (maker, name, grape, cuvée, region), written before you pick.`;

/** `read` comes first: the model writes what the label says before it picks. */
const PICK_FORM = {
  type: "object",
  additionalProperties: false,
  required: ["read", "pick", "sure"],
  properties: {
    read: { type: "string" },
    pick: { type: "integer" },
    sure: { type: "boolean" },
  },
} as const;

const CATALOG_PHOTO_INSTRUCTION =
  `You get two photos. The first is a bottle a member photographed in a shop. The second is a drinks catalog's product photo of one drink, whose catalog name is in the message. Decide whether the member's bottle is that very product: the same maker's same wine or bottling (ignore the vintage year).

Siblings of one maker share the label design and differ in a word or a colour (grape, cuvée, vineyard, classification, age, red or white): compare those words and the design carefully, and say \`same\` false when the member's label carries such a word the catalog photo's label does not, or the other way round. The catalog name may be worded differently from the label (extra or missing words, another spelling, the owner's name as maker): go by the two labels, not by the name. The catalog photo is small; when its words cannot be read and the design alone does not settle it, \`sure\` is false.

- \`differs\`: a few words on what differs, or "nothing".
- \`same\`: whether it is the same product.
- \`sure\`: true only when you would stake your name on \`same\`.`;

const CATALOG_PHOTO_FORM = {
  type: "object",
  additionalProperties: false,
  required: ["differs", "same", "sure"],
  properties: {
    differs: { type: "string" },
    same: { type: "boolean" },
    sure: { type: "boolean" },
  },
} as const;

/** A candidate as both questions name it. */
function nameAndMaker(candidate: LabelCandidate): string {
  return `${candidate.name} | maker: ${candidate.maker}`;
}

function jpeg(photo: string): Anthropic.ImageBlockParam {
  return {
    type: "image",
    source: { type: "base64", media_type: "image/jpeg", data: photo },
  };
}

export class AnthropicLabelJudge implements LabelJudge {
  private readonly client: Anthropic;

  constructor(apiKey: string, fetchImpl?: typeof fetch) {
    // A member is waiting on the answer: one quick second try, then give up.
    this.client = new Anthropic({
      apiKey,
      maxRetries: 1,
      timeout: 6_000,
      fetch: fetchImpl,
    });
  }

  async pickCandidate(
    photo: string,
    candidates: readonly LabelCandidate[],
  ): Promise<CandidatePick> {
    const { answer, usage } = await this.ask(
      "medium",
      PICK_INSTRUCTION,
      PICK_FORM,
      [
        jpeg(photo),
        {
          type: "text",
          text: JSON.stringify({
            candidates: candidates.map((candidate, index) => ({
              n: index + 1,
              name: nameAndMaker(candidate),
            })),
          }),
        },
      ],
    );
    const pick = answer.pick;
    if (
      typeof pick !== "number" || !Number.isInteger(pick) || pick < 0 ||
      pick > candidates.length
    ) {
      throw new LabelJudgeUnavailable("pick_out_of_range");
    }
    return { pick, sure: answer.sure === true, usage };
  }

  async matchCatalogPhoto(
    photo: string,
    candidate: LabelCandidate,
    catalogPhotoUrl: string,
  ): Promise<CatalogPhotoMatch> {
    // Two labels side by side take less thinking than a pick among ten: on
    // the test photos low effort accepted the same picks in half the time.
    const { answer, usage } = await this.ask(
      "low",
      CATALOG_PHOTO_INSTRUCTION,
      CATALOG_PHOTO_FORM,
      [
        jpeg(photo),
        { type: "image", source: { type: "url", url: catalogPhotoUrl } },
        {
          type: "text",
          text: `Catalog name of the second photo: ${nameAndMaker(candidate)}`,
        },
      ],
    );
    return { same: answer.same === true && answer.sure === true, usage };
  }

  /** One question, answered as the JSON object [form] describes. */
  private async ask(
    effort: "low" | "medium",
    instruction: string,
    form: Record<string, unknown>,
    content: Anthropic.ContentBlockParam[],
  ): Promise<{ answer: Record<string, unknown>; usage: JudgeUsage }> {
    let message: Anthropic.Message;
    try {
      message = await this.client.messages.create({
        model: MODEL,
        max_tokens: 3000,
        system: instruction,
        output_config: {
          effort,
          format: { type: "json_schema", schema: form },
        },
        messages: [{ role: "user", content }],
      });
    } catch (error) {
      if (error instanceof Anthropic.APIError) {
        throw new LabelJudgeUnavailable(`api_${error.status ?? "unreachable"}`);
      }
      throw error;
    }
    if (message.stop_reason !== "end_turn") {
      throw new LabelJudgeUnavailable(`stopped_${message.stop_reason}`);
    }
    const written = message.content
      .flatMap((block) => block.type === "text" ? [block.text] : [])
      .join("");
    let answer: unknown;
    try {
      answer = JSON.parse(written);
    } catch {
      throw new LabelJudgeUnavailable("answer_unreadable");
    }
    if (!answer || typeof answer !== "object" || Array.isArray(answer)) {
      throw new LabelJudgeUnavailable("answer_unreadable");
    }
    return {
      answer: answer as Record<string, unknown>,
      usage: {
        input_tokens: message.usage.input_tokens,
        output_tokens: message.usage.output_tokens,
      },
    };
  }
}
