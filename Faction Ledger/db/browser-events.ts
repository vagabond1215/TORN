type JsonObject = Record<string, unknown>;

function asInteger(value: unknown) {
  const number = Number(value);
  return Number.isSafeInteger(number) ? number : 0;
}

export function normalizedBrowserOccurredAt(
  summary: string,
  occurredAt: string | null,
  payload: JsonObject,
  allowPayloadEndedAt = true,
) {
  const endedAt = allowPayloadEndedAt ? asInteger(payload.endedAt) : 0;
  if (endedAt > 0) return new Date(endedAt * 1000).toISOString();
  const matches = Array.from(summary.matchAll(/(\d{2}):(\d{2}):(\d{2})\s*(\d{2})\/(\d{2})\/(\d{2})/g));
  const match = matches.at(-1);
  if (match) {
    return new Date(Date.UTC(
      2000 + Number(match[6]),
      Number(match[5]) - 1,
      Number(match[4]),
      Number(match[1]),
      Number(match[2]),
      Number(match[3]),
    )).toISOString();
  }
  if (occurredAt) {
    const legacy = occurredAt.match(/^(\d{2})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/);
    if (legacy) {
      return new Date(Date.UTC(
        2000 + Number(legacy[3]),
        Number(legacy[2]) - 1,
        Number(legacy[1]),
        Number(legacy[4]),
        Number(legacy[5]),
        Number(legacy[6]),
      )).toISOString();
    }
    const parsed = Date.parse(occurredAt);
    if (Number.isFinite(parsed)) return new Date(parsed).toISOString();
  }
  return null;
}
