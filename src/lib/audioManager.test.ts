import { beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAudio, subscribeAudioManager } from './audioManager';

describe('audio lifecycle recovery', () => {
  beforeEach(() => {
    window.localStorage.removeItem('sadesa-audio-enabled');
  });

  it('resumes previously enabled audio when the app regains focus', async () => {
    const mockContext = {
      state: 'running' as AudioContextState,
      currentTime: 0,
      destination: {},
      addEventListener: vi.fn(),
      resume: vi.fn(async () => {
        mockContext.state = 'running';
      }),
    };
    const context = mockContext as unknown as AudioContext;
    Object.defineProperty(window, 'AudioContext', {
      configurable: true,
      value: vi.fn(function AudioContextMock() { return context; }),
    });

    const stateChange = vi.fn();
    const unsubscribe = subscribeAudioManager('statechange', stateChange);
    await enableAudio({ playConfirmationTone: false });
    stateChange.mockClear();

    mockContext.state = 'suspended';
    window.dispatchEvent(new Event('focus'));
    await Promise.resolve();

    expect(context.resume).toHaveBeenCalledOnce();
    expect(mockContext.state).toBe('running');
    expect(stateChange).toHaveBeenCalled();
    unsubscribe();
  });
});
