// Public destination delivery API for message sends, cron.
// Exports mode selection, resolution, dispatch, and destination patch validation.
export { destinationsMode } from './types';
export { resolveDestinations } from './destinations';
export { dispatchDestinations, drainDestinationDeliveries } from './dispatch';
export { parseDestinationPatch } from './validation';
