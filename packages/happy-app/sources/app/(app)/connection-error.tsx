import React from 'react';
import { View, Text, ScrollView, TextInput, Pressable } from 'react-native';
import { useNavigation } from 'expo-router';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Typography } from '@/constants/Typography';
import { useSocketStatus } from '@/sync/storage';
import { getServerInfo } from '@/sync/serverConfig';
import { getHappyClientId } from '@/sync/apiSocket';
import { Modal } from '@/modal';
import { Ionicons } from '@expo/vector-icons';
import * as Clipboard from 'expo-clipboard';

function formatDetails(socketStatus: ReturnType<typeof useSocketStatus>): string {
    const { status, lastError, lastConnectedAt, lastDisconnectedAt } = socketStatus;
    const server = getServerInfo();
    const fmt = (t: number | null) => (t ? new Date(t).toISOString() : 'never');
    const lines: string[] = [];
    lines.push(`# Happy connection error`);
    lines.push('');
    lines.push(`captured-at: ${new Date().toISOString()}`);
    lines.push(`client: ${getHappyClientId()}`);
    lines.push(`server: ${server.hostname}${server.port ? ':' + server.port : ''} (custom=${server.isCustom})`);
    lines.push(`status: ${status}`);
    lines.push(`lastConnectedAt: ${fmt(lastConnectedAt)}`);
    lines.push(`lastDisconnectedAt: ${fmt(lastDisconnectedAt)}`);
    lines.push('');
    if (lastError) {
        lines.push(`## Error`);
        lines.push(`kind: ${lastError.kind}`);
        lines.push(`at: ${new Date(lastError.at).toISOString()}`);
        if (lastError.name) lines.push(`name: ${lastError.name}`);
        lines.push(`message: ${lastError.message}`);
        if (lastError.description) lines.push(`description: ${lastError.description}`);
        if (lastError.cause) lines.push(`cause: ${lastError.cause}`);
        if (lastError.extra) {
            lines.push(`extra:`);
            for (const [k, v] of Object.entries(lastError.extra)) {
                lines.push(`  ${k}: ${typeof v === 'string' ? v : JSON.stringify(v)}`);
            }
        }
        if (lastError.stack) {
            lines.push('');
            lines.push(`## Stack`);
            lines.push(lastError.stack);
        }
    } else {
        lines.push(`## Error`);
        lines.push(`(no error details captured)`);
    }
    return lines.join('\n');
}

export default function ConnectionErrorScreen() {
    const navigation = useNavigation();
    const { theme } = useUnistyles();
    const insets = useSafeAreaInsets();
    const socketStatus = useSocketStatus();

    const details = React.useMemo(() => formatDetails(socketStatus), [socketStatus]);

    const handleCopy = React.useCallback(async () => {
        try {
            await Clipboard.setStringAsync(details);
            Modal.alert('Copied', 'Connection error details copied to clipboard.');
        } catch {
            Modal.alert('Error', 'Failed to copy to clipboard.');
        }
    }, [details]);

    React.useLayoutEffect(() => {
        navigation.setOptions({
            headerRight: () => (
                <Pressable
                    onPress={handleCopy}
                    style={({ pressed }) => [styles.copyButton, { opacity: pressed ? 0.7 : 1 }]}
                >
                    <Ionicons name="copy-outline" size={22} color={theme.colors.header.tint} />
                </Pressable>
            ),
        });
    }, [navigation, handleCopy, theme]);

    return (
        <View style={[styles.container, { backgroundColor: theme.colors.surface }]}>
            <ScrollView
                style={styles.scroll}
                contentContainerStyle={[styles.scrollContent, { paddingBottom: insets.bottom + 24 }]}
                showsVerticalScrollIndicator
            >
                <TextInput
                    style={[styles.textInput, { color: theme.colors.text }]}
                    value={details}
                    multiline
                    editable={false}
                    selectTextOnFocus={false}
                    scrollEnabled={false}
                />
                <Text style={[styles.hint, { color: theme.colors.textSecondary }]}>
                    Tap the copy icon to copy these details, then share them with Claude Code for debugging.
                </Text>
            </ScrollView>
        </View>
    );
}

const styles = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
    },
    scroll: {
        flex: 1,
    },
    scrollContent: {
        padding: 16,
        flexGrow: 1,
    },
    textInput: {
        ...Typography.mono(),
        fontSize: 13,
        lineHeight: 18,
        textAlignVertical: 'top',
        backgroundColor: 'transparent',
        borderWidth: 0,
        padding: 0,
    },
    hint: {
        ...Typography.default(),
        fontSize: 12,
        marginTop: 24,
    },
    copyButton: {
        padding: 8,
        marginRight: 8,
        borderRadius: 8,
    },
}));
