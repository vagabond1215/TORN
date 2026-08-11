export type ScriptSyncErrorCode =
  | "membership_revalidation_required"
  | "membership_check_unavailable"
  | "identity_changed"
  | "faction_changed"
  | "invalid_session";

export class ScriptSyncAccessError extends Error {
  constructor(
    message: string,
    public readonly code: ScriptSyncErrorCode = "invalid_session",
    public readonly status = 401,
    public readonly currentFaction: { id: number; name: string } | null = null,
  ) {
    super(message);
  }
}

export function scriptSyncErrorResponse(error: ScriptSyncAccessError) {
  return Response.json({
    error: error.message,
    code: error.code,
    currentFaction: error.currentFaction,
  }, { status: error.status });
}
