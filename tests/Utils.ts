const MinControlPeriod = 21600;
const SixtyDaysConstant = 5184000;

export function checkPeriod(period: number): number {
    if (period < MinControlPeriod) {
        return MinControlPeriod;
    } else if (period > SixtyDaysConstant) {
        return SixtyDaysConstant;
    }
    return period;
}

export function extractContractData(input: string): Record<string, string | number> {
    return input
        .split('|')
        .reduce((acc, part) => {
            const [key, value] = part.split(':').map((item) => item.trim());
            if (key && value !== undefined) {
                const numericValue = Number(value);
                acc[key] = isNaN(numericValue) ? value : numericValue;
            }
            return acc;
        }, {} as Record<string, string | number>);
}