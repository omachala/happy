import {
    RevenueCatInterface,
    CustomerInfo,
    Product,
    Offerings,
    PurchaseResult,
    RevenueCatConfig,
    LogLevel,
    PaywallResult,
    PaywallOptions,
} from './types';

class RevenueCatStub implements RevenueCatInterface {
    configure(_config: RevenueCatConfig): void {}

    async getCustomerInfo(): Promise<CustomerInfo> {
        return {
            activeSubscriptions: {},
            entitlements: { all: {} },
            originalAppUserId: '',
            requestDate: new Date(),
        };
    }

    async getOfferings(): Promise<Offerings> {
        return { current: null, all: {} };
    }

    async getProducts(_productIds: string[]): Promise<Product[]> {
        return [];
    }

    async purchaseStoreProduct(_product: Product): Promise<PurchaseResult> {
        return { customerInfo: await this.getCustomerInfo() };
    }

    async syncPurchases(): Promise<void> {}

    setLogLevel(_level: LogLevel): void {}

    async presentPaywall(_options?: PaywallOptions): Promise<PaywallResult> {
        return PaywallResult.NOT_PRESENTED;
    }

    async presentPaywallIfNeeded(
        _options?: PaywallOptions & { requiredEntitlementIdentifier: string },
    ): Promise<PaywallResult> {
        return PaywallResult.NOT_PRESENTED;
    }
}

export default new RevenueCatStub();
