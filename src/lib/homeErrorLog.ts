// Structured error logging for Home page section fetches.
// Captures section name, fetch parameters, and an ISO timestamp so failures
// can be traced in the browser console (and later shipped to a collector).

export interface HomeSectionErrorEvent {
  section: string;
  queryKey: string;
  params: Record<string, unknown>;
  message: string;
  timestamp: string;
}

const MAX_EVENTS = 50;
const events: HomeSectionErrorEvent[] = [];

export function getHomeErrorEvents(): HomeSectionErrorEvent[] {
  return [...events];
}

export function logHomeSectionError(
  section: string,
  queryKey: string,
  params: Record<string, unknown>,
  error: unknown,
): HomeSectionErrorEvent {
  const event: HomeSectionErrorEvent = {
    section,
    queryKey,
    params,
    message: error instanceof Error ? error.message : String(error),
    timestamp: new Date().toISOString(),
  };

  events.push(event);
  if (events.length > MAX_EVENTS) events.shift();

  console.error(
    `[home:${section}] fetch failed at ${event.timestamp}`,
    {
      section: event.section,
      queryKey: event.queryKey,
      params: event.params,
      message: event.message,
      timestamp: event.timestamp,
    },
    error,
  );

  return event;
}
