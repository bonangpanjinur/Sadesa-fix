import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { ArrowRight, Sparkles, X } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import {
  FEATURE_TOUR_STEPS,
  getFirstUnseenFeatureTip,
  getFeatureTourRoleForVisitor,
  getFeatureTourStorageKey,
  markFeatureTipSeen,
  PUBLIC_BUYER_FEATURE_TOUR_STEPS,
  shouldAutoStartFeatureTour,
} from '@/lib/featureTour';

interface TourState {
  key: string | null;
  stepId: string | null;
  open: boolean;
}

interface TargetRect {
  top: number;
  left: number;
  width: number;
  height: number;
}

interface PopoverPosition {
  top: number;
  left: number;
  arrowLeft: number;
  side: 'top' | 'bottom';
}

const closedTour: TourState = { key: null, stepId: null, open: false };
const emptySteps: typeof FEATURE_TOUR_STEPS.buyer = [];
const POPOVER_WIDTH = 360;

function routeMatches(pathname: string, href: string): boolean {
  const route = href.split('?')[0];
  return pathname === route || (route !== '/' && pathname.startsWith(`${route}/`));
}

export function FeatureTour() {
  const { user, roles, loading, rolesLoading, merchantRoleRecoveryLoading } = useAuth();
  const { pathname } = useLocation();
  const navigate = useNavigate();
  const authReady = !loading && !rolesLoading && !merchantRoleRecoveryLoading;
  const role = authReady ? getFeatureTourRoleForVisitor(roles, pathname, Boolean(user)) : null;
  const steps = role
    ? role === 'buyer' && !user ? PUBLIC_BUYER_FEATURE_TOUR_STEPS : FEATURE_TOUR_STEPS[role]
    : emptySteps;
  const visitorId = user?.id ?? 'guest';
  const storageKey = role ? getFeatureTourStorageKey(visitorId, role) : null;
  const [tour, setTour] = useState<TourState>(closedTour);
  const autoStartAttemptedKeysRef = useRef(new Set<string>());
  const targetElementRef = useRef<HTMLElement | null>(null);
  const [targetRect, setTargetRect] = useState<TargetRect | null>(null);
  const [popoverPosition, setPopoverPosition] = useState<PopoverPosition | null>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
  const currentStep = tour.key === storageKey ? steps.find((step) => step.id === tour.stepId) : undefined;
  const currentStepIndex = currentStep ? steps.findIndex((step) => step.id === currentStep.id) : -1;

  useEffect(() => {
    if (!authReady) {
      setTour(closedTour);
      return;
    }
    if (!role || !storageKey) {
      setTour(closedTour);
      return;
    }
    // React StrictMode replays effects on mount. Guard the start attempt so the
    // first step marked below does not make that replay skip ahead to step two.
    if (autoStartAttemptedKeysRef.current.has(storageKey)) return;
    autoStartAttemptedKeysRef.current.add(storageKey);

    let shouldStart = true;
    try {
      shouldStart = shouldAutoStartFeatureTour(window.localStorage, storageKey);
    } catch {
      // Browser storage may be disabled; keep the app usable without persistence.
    }
    if (!shouldStart) {
      setTour({ key: storageKey, stepId: null, open: false });
      return;
    }

    const firstStep = steps[0];
    if (firstStep) {
      try {
        markFeatureTipSeen(window.localStorage, storageKey, firstStep.id);
      } catch {
        // Best-effort persistence.
      }
    }
    setTour({ key: storageKey, stepId: firstStep?.id ?? null, open: Boolean(firstStep) });
  }, [authReady, role, steps, storageKey, user]);

  // Keep an active tour on the page that contains its current feature.
  useEffect(() => {
    if (!tour.open || !currentStep || routeMatches(pathname, currentStep.href)) return;
    navigate(currentStep.href, { replace: true });
  }, [currentStep, navigate, pathname, tour.open]);

  useEffect(() => {
    if (!tour.open || !currentStep) {
      targetElementRef.current = null;
      setTargetRect(null);
      setPopoverPosition(null);
      return;
    }

    targetElementRef.current = null;
    setTargetRect(null);
    setPopoverPosition(null);
    const selectors = currentStep.target === 'page-title'
      ? ['[data-feature-tour="page-title"]', 'main h1', 'main h2', 'header h1', 'h1', 'h2']
      : [`[data-feature-tour="${currentStep.target}"]`, '[data-feature-tour="page-title"]', 'main h1', 'main h2', 'h1', 'h2'];
    let target: HTMLElement | null = null;
    let frame = 0;
    let observer: MutationObserver | null = null;
    let retryTimer = 0;
    const updateTargetRect = () => {
      if (!target?.isConnected) return;
      const rect = target.getBoundingClientRect();
      setTargetRect({ top: rect.top, left: rect.left, width: rect.width, height: rect.height });
    };
    const attachTarget = () => {
      target = selectors
        .map((selector) => document.querySelector<HTMLElement>(selector))
        .find((element) => element && element.getClientRects().length > 0) ?? null;
      if (!target) return false;
      targetElementRef.current = target;
      target.scrollIntoView?.({ behavior: 'smooth', block: 'center', inline: 'nearest' });
      frame = window.requestAnimationFrame(updateTargetRect);
      window.addEventListener('resize', updateTargetRect);
      window.addEventListener('scroll', updateTargetRect, true);
      return true;
    };
    observer = new MutationObserver(() => {
      if (attachTarget()) observer?.disconnect();
    });
    observer.observe(document.body, { childList: true, subtree: true });
    const initialTargetFound = attachTarget();
    if (initialTargetFound) observer.disconnect();
    else {
      setTargetRect(null);
      retryTimer = window.setTimeout(() => {
        if (!targetElementRef.current?.isConnected && attachTarget()) observer?.disconnect();
      }, 180);
    }
    return () => {
      window.clearTimeout(retryTimer);
      observer?.disconnect();
      window.cancelAnimationFrame(frame);
      window.removeEventListener('resize', updateTargetRect);
      window.removeEventListener('scroll', updateTargetRect, true);
    };
  }, [currentStep, pathname, tour.open]);

  useLayoutEffect(() => {
    if (!targetRect || !popoverRef.current) {
      setPopoverPosition(null);
      return;
    }
    const width = Math.min(POPOVER_WIDTH, window.innerWidth - 24);
    const height = popoverRef.current.getBoundingClientRect().height || 260;
    const below = targetRect.top + targetRect.height + height + 16 <= window.innerHeight - 12;
    const top = below
      ? targetRect.top + targetRect.height + 12
      : Math.max(12, targetRect.top - height - 12);
    const targetCenter = targetRect.left + targetRect.width / 2;
    const left = Math.min(Math.max(12, targetCenter - width / 2), window.innerWidth - width - 12);
    const arrowLeft = Math.min(Math.max(12, targetCenter - left - 6), width - 24);
    setPopoverPosition({ top, left, arrowLeft, side: below ? 'bottom' : 'top' });
  }, [targetRect, currentStep]);

  if (!authReady || !role || !storageKey || !tour.open || !currentStep) return null;

  const dismissTour = () => {
    try {
      markFeatureTipSeen(window.localStorage, storageKey, currentStep.id);
    } catch {
      // Best-effort persistence.
    }
    setTour((current) => ({ ...current, open: false }));
  };

  const advance = () => {
    let seen: string[] = [];
    try {
      seen = markFeatureTipSeen(window.localStorage, storageKey, currentStep.id);
    } catch {
      seen = [currentStep.id];
    }
    const nextUnseen = getFirstUnseenFeatureTip(steps, seen);
    if (nextUnseen) {
      try {
        markFeatureTipSeen(window.localStorage, storageKey, nextUnseen.id);
      } catch {
        // Best-effort persistence.
      }
      setTour({ key: storageKey, stepId: nextUnseen.id, open: true });
      navigate(nextUnseen.href, { replace: true });
      return;
    }
    setTour({ key: storageKey, stepId: null, open: false });
  };

  const progress = ((currentStepIndex + 1) / steps.length) * 100;
  const highlightStyle = targetRect ? {
    top: targetRect.top - 6,
    left: targetRect.left - 6,
    width: targetRect.width + 12,
    height: targetRect.height + 12,
    boxShadow: '0 0 0 9999px rgba(15, 23, 42, 0.42)',
  } : undefined;

  return (
    <>
      {targetRect && (
        <div
          aria-hidden="true"
          className="pointer-events-none fixed z-[79] rounded-xl border-2 border-primary bg-transparent shadow-[0_0_0_3px_rgba(255,255,255,0.92)]"
          style={highlightStyle}
        />
      )}
      <div
        ref={popoverRef}
        className="fixed z-[90] w-[min(360px,calc(100vw-24px))]"
        style={popoverPosition ? { top: popoverPosition.top, left: popoverPosition.left } : { bottom: '1rem', right: '1rem' }}
        role="dialog"
        aria-label={`Panduan fitur: ${currentStep.title}`}
        aria-live="polite"
      >
        {targetRect && popoverPosition && (
          <span
            aria-hidden="true"
            className={`absolute z-10 h-3 w-3 rotate-45 border bg-background ${popoverPosition.side === 'bottom' ? '-top-1.5 border-b-0 border-r-0' : '-bottom-1.5 border-l-0 border-t-0'}`}
            style={{ left: popoverPosition.arrowLeft }}
          />
        )}
        <Card className="relative overflow-hidden border-primary/30 bg-background shadow-2xl shadow-black/25">
          <div className="h-1 bg-muted"><div className="h-full bg-primary transition-all" style={{ width: `${progress}%` }} /></div>
          <CardHeader className="flex flex-row items-start justify-between gap-3 space-y-0 p-4 pb-2">
            <div className="min-w-0">
              <p className="mb-1 flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-primary"><Sparkles className="h-3.5 w-3.5" />Pengenalan fitur · {currentStepIndex + 1}/{steps.length}</p>
              <h2 className="text-base font-semibold leading-snug">{currentStep.title}</h2>
            </div>
            <Button type="button" variant="ghost" size="icon" className="-mr-2 -mt-2 h-8 w-8 shrink-0" onClick={dismissTour} aria-label="Jangan tampilkan lagi">
              <X className="h-4 w-4" />
            </Button>
          </CardHeader>
          <CardContent className="space-y-3 px-4 pb-4 pt-1">
            <p className="text-sm leading-relaxed text-muted-foreground">{currentStep.description}</p>
            <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
              <Link to={currentStep.href} className="text-xs font-medium text-primary underline-offset-4 hover:underline">{currentStep.linkLabel}</Link>
              <div className="ml-auto flex shrink-0 items-center gap-2">
                <Button type="button" variant="ghost" size="sm" className="h-9 px-2 text-xs" onClick={dismissTour}>Jangan tampilkan lagi</Button>
                <Button type="button" size="sm" className="h-9" onClick={advance}>
                  {currentStepIndex === steps.length - 1 ? 'Selesai' : 'Berikutnya'}
                  {currentStepIndex !== steps.length - 1 && <ArrowRight className="ml-1.5 h-3.5 w-3.5" />}
                </Button>
              </div>
            </div>
            <p className="text-[10px] text-muted-foreground">Petunjuk ini menunjuk langsung ke fitur yang sedang dijelaskan.</p>
          </CardContent>
        </Card>
      </div>
    </>
  );
}
