import { useContext } from 'react';
import { PWAContext, type PWAContextValue } from './PWAContext';

export function usePWA(): PWAContextValue {
  const context = useContext(PWAContext);
  if (!context) throw new Error('usePWA must be used within PWAProvider');
  return context;
}
