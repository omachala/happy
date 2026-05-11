import * as React from 'react';
import { Pressable } from 'react-native';
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import { useUnistyles } from 'react-native-unistyles';

export const HeaderLogo = React.memo(() => {
    const { theme } = useUnistyles();
    const router = useRouter();
    return (
        <Pressable
            onPress={() => router.navigate('/settings')}
            hitSlop={15}
            style={{
                width: 32,
                height: 32,
                alignItems: 'center',
                justifyContent: 'center',
            }}
        >
            <Image
                source={require('@/assets/images/logo-black.png')}
                contentFit="contain"
                style={{ width: 24, height: 24 }}
                tintColor={theme.colors.header.tint}
            />
        </Pressable>
    );
});
