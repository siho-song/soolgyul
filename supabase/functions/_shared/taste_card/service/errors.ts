// The errors the card service throws, kept apart from the engine so the
// shared error mapper can tell them apart without loading the card engine.

/** The request body does not follow the wire contract. */
export class TasteCardContractError extends Error {
  constructor(public readonly code: string, public readonly path: string) {
    super(`${code}:${path}`);
    this.name = "TasteCardContractError";
  }
}

/** The conversion token in the request is missing, forged or expired. */
export class ConversionTokenError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "ConversionTokenError";
  }
}

/** A gate or rule of the card flow refused the request. */
export class TasteCardOrchestrationError extends Error {
  constructor(public readonly code: string, message = code) {
    super(message);
    this.name = "TasteCardOrchestrationError";
  }
}

/**
 * A store call failed, or what it returned does not read. The code is the
 * database's (SQLSTATE) when it gave one. `transient` when trying again later
 * may succeed: a timeout, a dropped connection, an unavailable server.
 */
export class TasteCardRepositoryError extends Error {
  constructor(
    public readonly code: string,
    message = code,
    public readonly transient = false,
  ) {
    super(message);
    this.name = "TasteCardRepositoryError";
  }
}
