import Constants from 'expo-constants';
import { requireOptionalNativeModule } from 'expo-modules-core';

export interface AppConfig {
    postHogKey?: string;
    revenueCatAppleKey?: string;
    revenueCatGoogleKey?: string;
    revenueCatStripeKey?: string;
    elevenLabsAgentId?: string;
    consoleLoggingDefault?: boolean;
    serverUrl?: string;
}

/**
 * Loads app configuration from various manifest sources.
 */
export function loadAppConfig(): AppConfig {
    const config: Partial<AppConfig> = {};

    try {
        const ExponentConstants = requireOptionalNativeModule('ExponentConstants');
        if (ExponentConstants && ExponentConstants.manifest) {
            let exponentManifest = ExponentConstants.manifest;
            if (typeof exponentManifest === 'string') {
                try {
                    exponentManifest = JSON.parse(exponentManifest);
                } catch (e) {
                    console.warn('[loadAppConfig] Failed to parse ExponentConstants.manifest:', e);
                }
            }
            const appConfig = exponentManifest?.extra?.app;
            if (appConfig && typeof appConfig === 'object') {
                Object.assign(config, appConfig);
            }
        }
    } catch (e) {
        console.warn('[loadAppConfig] Error accessing ExponentConstants:', e);
    }

    try {
        if (Constants.expoConfig?.extra?.app) {
            const appConfig = Constants.expoConfig.extra.app;
            if (typeof appConfig === 'object') {
                Object.assign(config, appConfig);
            }
        }
    } catch (e) {
        console.warn('[loadAppConfig] Error accessing Constants.expoConfig:', e);
    }

    if (process.env.EXPO_PUBLIC_SERVER_URL && config.serverUrl !== process.env.EXPO_PUBLIC_SERVER_URL) {
        config.serverUrl = process.env.EXPO_PUBLIC_SERVER_URL;
    }

    return config as AppConfig;
}
