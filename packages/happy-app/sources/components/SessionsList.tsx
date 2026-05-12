import React from 'react';
import { View, FlatList } from 'react-native';
import { usePathname } from 'expo-router';
import { SessionListViewItem } from '@/sync/storage';
import { ActiveSessionsGroupCompact } from './ActiveSessionsGroupCompact';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useVisibleSessionListViewData } from '@/hooks/useVisibleSessionListViewData';
import { StyleSheet } from 'react-native-unistyles';
import { useIsTablet } from '@/utils/responsive';
import { requestReview } from '@/utils/requestReview';
import { UpdateBanner } from './UpdateBanner';
import { layout } from './layout';

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
        flexDirection: 'row',
        justifyContent: 'center',
        alignItems: 'stretch',
        backgroundColor: theme.colors.groupped.background,
    },
    contentContainer: {
        flex: 1,
        maxWidth: layout.maxWidth,
    },
}));

export function SessionsList() {
    const styles = stylesheet;
    const safeArea = useSafeAreaInsets();
    const data = useVisibleSessionListViewData();
    const pathname = usePathname();
    const isTablet = useIsTablet();

    React.useEffect(() => {
        if (data && data.length > 0) {
            requestReview();
        }
    }, [data && data.length > 0]);

    if (!data) {
        return (
            <View style={styles.container} />
        );
    }

    const keyExtractor = React.useCallback((item: SessionListViewItem) => {
        return item.type === 'active-sessions' ? 'active-sessions' : `${item.type}`;
    }, []);

    const renderItem = React.useCallback(({ item }: { item: SessionListViewItem }) => {
        if (item.type !== 'active-sessions') return null;

        let selectedId: string | undefined;
        if (isTablet && pathname.startsWith('/session/')) {
            const parts = pathname.split('/');
            selectedId = parts[2];
        }

        return (
            <ActiveSessionsGroupCompact
                sessions={item.sessions}
                selectedSessionId={selectedId}
            />
        );
    }, [isTablet, pathname]);

    const HeaderComponent = React.useCallback(() => <UpdateBanner />, []);

    return (
        <View style={styles.container}>
            <View style={styles.contentContainer}>
                <FlatList
                    data={data}
                    renderItem={renderItem}
                    keyExtractor={keyExtractor}
                    contentContainerStyle={{ paddingBottom: safeArea.bottom + 128, maxWidth: layout.maxWidth }}
                    ListHeaderComponent={HeaderComponent}
                />
            </View>
        </View>
    );
}
