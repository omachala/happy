import * as React from 'react';
import { View, ActivityIndicator, Text, Pressable } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { useSocketStatus, useRealtimeStatus } from '@/sync/storage';
import { useVisibleSessionListViewData } from '@/hooks/useVisibleSessionListViewData';
import { useIsTablet } from '@/utils/responsive';
import { useRouter } from 'expo-router';
import { EmptySessionsTablet } from './EmptySessionsTablet';
import { SessionsList } from './SessionsList';
import { SessionsListWrapper } from './SessionsListWrapper';
import { Header } from './navigation/Header';
import { HeaderLogo } from './HeaderLogo';
import { VoiceAssistantStatusBar } from './VoiceAssistantStatusBar';
import { StatusDot } from './StatusDot';
import { Ionicons } from '@expo/vector-icons';
import { Typography } from '@/constants/Typography';
import { t } from '@/text';

interface MainViewProps {
    variant: 'phone' | 'sidebar';
}

const styles = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
    },
    phoneContainer: {
        flex: 1,
    },
    sidebarContentContainer: {
        flex: 1,
        flexBasis: 0,
        flexGrow: 1,
    },
    loadingContainerWrapper: {
        flex: 1,
        flexBasis: 0,
        flexGrow: 1,
        backgroundColor: theme.colors.groupped.background,
    },
    loadingContainer: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        paddingBottom: 32,
    },
    tabletLoadingContainer: {
        flex: 1,
        flexBasis: 0,
        flexGrow: 1,
        justifyContent: 'center',
        alignItems: 'center',
    },
    emptyStateContainer: {
        flex: 1,
        flexBasis: 0,
        flexGrow: 1,
        flexDirection: 'column',
        backgroundColor: theme.colors.groupped.background,
    },
    emptyStateContentContainer: {
        flex: 1,
        flexBasis: 0,
        flexGrow: 1,
    },
    titleContainer: {
        flex: 1,
        alignItems: 'center',
    },
    titleText: {
        fontSize: 17,
        color: theme.colors.header.tint,
        fontWeight: '600',
        ...Typography.default('semiBold'),
    },
    statusContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        marginTop: -2,
    },
    statusText: {
        fontSize: 12,
        fontWeight: '500',
        lineHeight: 16,
        ...Typography.default(),
    },
    headerButton: {
        width: 32,
        height: 32,
        alignItems: 'center',
        justifyContent: 'center',
    },
}));

const HeaderTitle = React.memo(() => {
    const { theme } = useUnistyles();
    const socketStatus = useSocketStatus();

    const connectionStatus = React.useMemo(() => {
        const { status } = socketStatus;
        switch (status) {
            case 'connected':
                return { color: theme.colors.status.connected, isPulsing: false, text: t('status.connected') };
            case 'connecting':
                return { color: theme.colors.status.connecting, isPulsing: true, text: t('status.connecting') };
            case 'disconnected':
                return { color: theme.colors.status.disconnected, isPulsing: false, text: t('status.disconnected') };
            case 'error':
                return { color: theme.colors.status.error, isPulsing: false, text: t('status.error') };
            default:
                return { color: theme.colors.status.default, isPulsing: false, text: '' };
        }
    }, [socketStatus, theme]);

    return (
        <View style={styles.titleContainer}>
            <Text style={styles.titleText}>{t('tabs.sessions')}</Text>
            {connectionStatus.text && (
                <View style={styles.statusContainer}>
                    <StatusDot color={connectionStatus.color} isPulsing={connectionStatus.isPulsing} size={6} style={{ marginRight: 4 }} />
                    <Text style={[styles.statusText, { color: connectionStatus.color }]}>{connectionStatus.text}</Text>
                </View>
            )}
        </View>
    );
});

const HeaderRight = React.memo(() => {
    const router = useRouter();
    const { theme } = useUnistyles();
    return (
        <Pressable onPress={() => router.navigate('/new')} hitSlop={15} style={styles.headerButton}>
            <Ionicons name="add-outline" size={28} color={theme.colors.header.tint} />
        </Pressable>
    );
});

export const MainView = React.memo(({ variant }: MainViewProps) => {
    const { theme } = useUnistyles();
    const sessionListViewData = useVisibleSessionListViewData();
    const isTablet = useIsTablet();
    const realtimeStatus = useRealtimeStatus();

    if (variant === 'sidebar') {
        if (sessionListViewData === null) {
            return (
                <View style={styles.sidebarContentContainer}>
                    <View style={styles.tabletLoadingContainer}>
                        <ActivityIndicator size="small" color={theme.colors.textSecondary} />
                    </View>
                </View>
            );
        }
        if (sessionListViewData.length === 0) {
            return (
                <View style={styles.sidebarContentContainer}>
                    <View style={styles.emptyStateContainer}>
                        <EmptySessionsTablet />
                    </View>
                </View>
            );
        }
        return (
            <View style={styles.sidebarContentContainer}>
                <SessionsList />
            </View>
        );
    }

    if (isTablet) {
        return <View style={styles.emptyStateContentContainer} />;
    }

    return (
        <View style={styles.phoneContainer}>
            <View style={{ backgroundColor: theme.colors.groupped.background }}>
                <Header
                    title={<HeaderTitle />}
                    headerRight={() => <HeaderRight />}
                    headerLeft={() => <HeaderLogo />}
                    headerShadowVisible={false}
                    headerTransparent={true}
                />
                {realtimeStatus !== 'disconnected' && <VoiceAssistantStatusBar variant="full" />}
            </View>
            <SessionsListWrapper />
        </View>
    );
});
