// Formats countdowns consistently across decision surfaces.
// Thresholds are reported only when an active countdown crosses them.

export function remainingTime(seconds: number, locale: string): string {
	const unit = seconds >= 60 ? 'minute' : 'second';
	const value = unit === 'minute' ? Math.ceil(seconds / 60) : seconds;
	if (locale === 'en') return `${value} ${unit === 'minute' ? 'min' : 'sec'}`;
	return new Intl.NumberFormat(locale, { style: 'unit', unit, unitDisplay: 'short' }).format(value);
}

export function crossedThreshold(previous: number, current: number): number | undefined {
	return [60, 300].find((threshold) => current > 0 && previous > threshold && current <= threshold);
}
