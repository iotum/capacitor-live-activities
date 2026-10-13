import { WebPlugin } from '@capacitor/core';
import type { PermissionState, PluginListenerHandle } from '@capacitor/core';

import type {
  ApplyEventOptions,
  ApplyEventResult,
  ActivityInfo,
  ActivityStateChangedEvent,
  EndOptions,
  LiveActivitiesPlugin,
  PushTokenResult,
  PushTokenUpdatedEvent,
  PushToStartTokenUpdatedEvent,
  StartOptions,
  UpdateOptions,
} from './definitions';

export class LiveActivitiesWeb extends WebPlugin implements LiveActivitiesPlugin {
  async checkPermissions(): Promise<{ notifications: PermissionState }> {
    return { notifications: 'denied' };
  }

  async requestPermissions(): Promise<{ notifications: PermissionState }> {
    return { notifications: 'denied' };
  }

  async applyEvent(_options: ApplyEventOptions): Promise<ApplyEventResult> {
    void _options;
    throw this.unimplemented('Native event handling is only supported on Android.');
  }

  async configureTokenUpload(_options: { url: string; origin: string }): Promise<void> {
    throw this.unimplemented('Native token uploads are only supported on iOS.');
  }

  async resetTokenUpload(): Promise<void> {
    throw this.unimplemented('Native token uploads are only supported on iOS.');
  }

  async isSupported(): Promise<{ supported: boolean }> {
    return { supported: false };
  }

  async areActivitiesEnabled(): Promise<{ enabled: boolean }> {
    return { enabled: false };
  }

  async start(_options: StartOptions): Promise<{ activityId: string }> {
    throw this.unimplemented('Live Activities are not supported on web.');
  }

  async update(_options: UpdateOptions): Promise<void> {
    throw this.unimplemented('Live Activities are not supported on web.');
  }

  async end(_options: EndOptions): Promise<void> {
    throw this.unimplemented('Live Activities are not supported on web.');
  }

  async getActiveActivities(): Promise<{ activities: ActivityInfo[] }> {
    return { activities: [] };
  }

  async getPushToken(_options: { activityId: string }): Promise<PushTokenResult> {
    return { token: null, type: null };
  }

  async getPushToStartToken(): Promise<PushTokenResult> {
    return { token: null, type: null };
  }

  async addListener(
    _eventName: 'activityStateChanged' | 'pushTokenUpdated' | 'pushToStartTokenUpdated',
    _listenerFunc: (
      event: ActivityStateChangedEvent | PushTokenUpdatedEvent | PushToStartTokenUpdatedEvent,
    ) => void,
  ): Promise<PluginListenerHandle> {
    return { remove: async () => undefined };
  }

  async removeAllListeners(): Promise<void> {
    return undefined;
  }
}
