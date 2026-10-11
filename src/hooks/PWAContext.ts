import { createContext } from 'react';
import type { PwaDeviceSession } from '@/lib/pwaDevice';

export interface PWAContextValue {
  isInstallable: boolean;
  isInstalled: boolean;
  isOnline: boolean;
  isUpdateAvailable: boolean;
  isUpdating: boolean;
  device: PwaDeviceSession | null;
  deviceRevoked: boolean;
  heartbeat: (syncAt?: string | null) => Promise<PwaDeviceSession | null>;
  installApp: () => Promise<boolean>;
  updateApp: () => Promise<void>;
  canInstall: boolean;
}

export const PWAContext = createContext<PWAContextValue | null>(null);
