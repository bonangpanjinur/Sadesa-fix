import { useEffect, useState, type ReactNode } from 'react';

interface SplashScreenProps {
  children: ReactNode;
}

const SPLASH_MINIMUM_TIME = 1100;
const SPLASH_EXIT_TIME = 420;

export function SplashScreen({ children }: SplashScreenProps) {
  const [visible, setVisible] = useState(true);
  const [exiting, setExiting] = useState(false);

  useEffect(() => {
    const exitTimer = window.setTimeout(() => setExiting(true), SPLASH_MINIMUM_TIME);
    const hideTimer = window.setTimeout(() => setVisible(false), SPLASH_MINIMUM_TIME + SPLASH_EXIT_TIME);

    return () => {
      window.clearTimeout(exitTimer);
      window.clearTimeout(hideTimer);
    };
  }, []);

  return (
    <>
      <div
        aria-hidden={!visible}
        className={`fixed inset-0 z-[100] flex items-center justify-center overflow-hidden bg-[#fffaf4] transition-opacity duration-[420ms] ${
          visible ? 'opacity-100' : 'pointer-events-none opacity-0'
        }`}
      >
        <div className="absolute -left-20 -top-24 h-64 w-64 rounded-full bg-[#006b45]/10 blur-3xl" />
        <div className="absolute -bottom-24 -right-16 h-72 w-72 rounded-full bg-[#e51c2a]/10 blur-3xl" />

        <div
          className={`relative flex w-[min(86vw,390px)] flex-col items-center text-center transition-all duration-700 ${
            exiting ? 'translate-y-[-10px] scale-[1.03] opacity-0' : 'translate-y-0 scale-100 opacity-100'
          }`}
        >
          <div className="relative mb-7 flex w-full items-center justify-center">
            <div className="absolute h-40 w-40 rounded-full border border-[#006b45]/10" />
            <div className="absolute h-32 w-32 rounded-full border border-[#e51c2a]/10 [animation:spin_10s_linear_infinite]" />
            <div className="relative flex h-24 w-24 items-center justify-center rounded-[28px] bg-white p-2 shadow-[0_18px_45px_-18px_rgba(0,70,45,0.45)]">
              <img
                src="/branding/sadesa-icon-192.png"
                alt=""
                className="h-full w-full object-contain"
              />
            </div>
          </div>

          <img
            src="/branding/sadesa-logo.png"
            alt="SaDesa"
            className="w-[min(80vw,340px)] object-contain"
          />
          <p className="mt-4 text-[11px] font-bold uppercase tracking-[0.24em] text-[#006b45]/70">
            Dari desa untuk Indonesia
          </p>

          <div className="mt-8 flex items-center gap-1.5" aria-label="Memuat aplikasi" role="status">
            <span className="h-1.5 w-1.5 rounded-full bg-[#006b45] [animation:splash-pulse_1.2s_ease-in-out_infinite]" />
            <span className="h-1.5 w-1.5 rounded-full bg-[#e51c2a] [animation:splash-pulse_1.2s_0.2s_ease-in-out_infinite]" />
            <span className="h-1.5 w-1.5 rounded-full bg-[#f0a51a] [animation:splash-pulse_1.2s_0.4s_ease-in-out_infinite]" />
          </div>
        </div>
      </div>

      <div className={`transition-opacity duration-500 ${visible ? 'opacity-0' : 'opacity-100'}`}>
        {children}
      </div>
    </>
  );
}