import * as React from 'react';
import { SessionListViewItem, useSessionListViewData } from '@/sync/storage';

// Home screen shows only the active-sessions group. Archived/inactive
// sessions are intentionally hidden from this view — accessible elsewhere
// if/when we add a dedicated archive screen.
export function useVisibleSessionListViewData(): SessionListViewItem[] | null {
    const data = useSessionListViewData();

    return React.useMemo(() => {
        if (!data) {
            return data;
        }
        return data.filter(item => item.type === 'active-sessions');
    }, [data]);
}
