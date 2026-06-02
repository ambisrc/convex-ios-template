import type { AssistantOperation } from "./operations";

export function interpretCommand(text: string): {
  operations: AssistantOperation[];
  summary: string;
} {
  const operations = parseOperations(text.trim());
  return {
    operations,
    summary: summarize(operations),
  };
}

function parseOperations(text: string): AssistantOperation[] {
  if (!text) {
    throw new Error("EMPTY_COMMAND");
  }

  const body = text
    .replace(/^create\s+(a\s+)?(note|entry)\s+(saying|called|named)\s+/i, "")
    .trim();

  if (!body) {
    throw new Error("EMPTY_COMMAND");
  }

  return [{ type: "create_entry", body }];
}

function summarize(operations: AssistantOperation[]) {
  if (operations.length === 1 && operations[0].type === "create_entry") {
    return `Created entry: ${operations[0].body}.`;
  }
  return `Applied ${operations.length} operations.`;
}
