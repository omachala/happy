type Tracking = {
    capture: (event: string, properties?: Record<string, unknown>) => void;
    identify: (id: string, properties?: Record<string, unknown>) => void;
    reset: () => void;
    optIn: () => void;
    optOut: () => void;
    screen: (name: string, properties?: Record<string, unknown>) => void;
    getFeatureFlag: (key: string) => unknown;
    featureFlags?: {
        overrideFeatureFlags?: (options: { flags: Record<string, string | boolean> }) => void;
    };
};

export const tracking: Tracking | null = null;
