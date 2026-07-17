/**
 * True for `parseStrictJsonLines` failures, which are deterministic — the same
 * content fails identically on every retry — so callers can degrade to
 * "log unavailable" instead of crash-looping an at-least-once trigger.
 * Transient IO errors return false and should be rethrown for retry.
 */
export function isDeterministicJsonlError(error: unknown): boolean {
  return error instanceof Error && error.message.startsWith("invalid_jsonl:");
}

export function parseStrictJsonLines(
  content: string,
  fileLabel: string
): Record<string, unknown>[] {
  const rows: Record<string, unknown>[] = [];
  const lines = content.split(/\r?\n/);

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].trim();
    if (line.length === 0) {
      continue;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(line) as unknown;
    } catch {
      throw new Error(`invalid_jsonl:${fileLabel}:${index + 1}`);
    }

    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error(`invalid_jsonl:${fileLabel}:${index + 1}`);
    }

    rows.push(parsed as Record<string, unknown>);
  }

  return rows;
}
