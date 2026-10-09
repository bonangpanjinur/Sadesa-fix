import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { ArrowRight, Sparkles, X } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import {
  FEATURE_TOUR_STEPS,
  getFirstUnseenFeatureTip,
  getFeatureTourRoleForVisitor,
  getFeatureTourSessionKey,
  getFeatureTourStorageKey,
  markFeatureTipSeen,
  readSeenFeatureTips,
} from '@/lib/featureTour';

interface TourState {
  key: string | null;
  stepId: string | null;
  open: boolean;
}

const closedTour: TourState = { key: null, stepId: null, open: false };
const emptySteps: typeof FEATURE_TOUR_STEPS.buyer = [];

export function FeatureTour() {
  const { user, roles, loading, rolesLoading, merchantRoleRecoveryLoading } = useAuth();
  const { pathname } = useLocation();
  const authReady = !loading && !rolesLoading && !merchantRoleRecoveryLoading;
  const role = authReady ? getFeatureTourRoleForVisitor(roles, pathname, Boolean(user)) : null;
  const steps = role ? FEATURE_TOUR_STEPS[role] : emptySteps;
  const visitorId = user?.id ?? 'guest';
  const storageKey = role ? getFeatureTourStorageKey(visitorId, role) : null;
  const sessionKey = role ? getFeatureTourSessionKey(visitorId, role) : null;
  const [tour, setTour] = useState<TourState>(closedTour);
  const currentStep = tour.key === storageKey ? steps.find((step) => step.id === tour.stepId) : undefined;
  const currentStepIndex = currentStep ? steps.findIndex((step) => step.id === currentStep.id) : -1;

  useEffect(() => {
    if (!authReady) {
      setTour(closedTour);
      return;
    }
    if (!role || !storageKey || !sessionKey) {
      setTour(closedTour);
      return;
    }

    let deferred = false;
    try {
      deferred = window.sessionStorage.getItem(sessionKey) === '1';
    } catch {
      // A blocked session store must not prevent the guide from working.
    }
    let seen: string[] = [];
    try {
      seen = readSeenFeatureTips(window.localStorage, storageKey);
    } catch {
      // Browser storage may be disabled; keep the app usable without persistence.
    }
    const firstUnseen = getFirstUnseenFeatureTip(steps, seen);
    if (!deferred && firstUnseen) {
      try {
        markFeatureTipSeen(window.localStorage, storageKey, firstUnseen.id);
      } catch {
        // Best-effort persistence.
      }
    }
    setTour({ key: storageKey, stepId: firstUnseen?.id ?? null, open: !deferred && Boolean(firstUnseen) });
  }, [authReady, role, sessionKey, steps, storageKey, user]);

  if (!authReady || !role || !storageKey || !sessionKey || !tour.open || !currentStep) return null;

  const closeForNow = () => {
    try {
      markFeatureTipSeen(window.localStorage, storageKey, currentStep.id);
    } catch {
      // Best-effort persistence.
    }
    try {
      window.sessionStorage.setItem(sessionKey, '1');
    } catch {
      // Still close for this render if storage is unavailable.
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
    }
    setTour({ key: storageKey, stepId: nextUnseen?.id ?? null, open: Boolean(nextUnseen) });
  };

  const progress = ((currentStepIndex + 1) / steps.length) * 100;

  return (
    <div
      className="fixed inset-x-3 bottom-[calc(5.5rem+env(safe-area-inset-bottom))] z-[80] mx-auto w-auto max-w-sm sm:inset-x-auto sm:bottom-5 sm:right-5 sm:mx-0"
      role="dialog"
      aria-label="Pengenalan fitur aplikasi"
      aria-live="polite"
    >
      <Card className="overflow-hidden border-primary/25 bg-background shadow-2xl shadow-black/15">
        <div className="h-1 bg-muted"><div className="h-full bg-primary transition-all" style={{ width: `${progress}%` }} /></div>
        <CardHeader className="flex flex-row items-start justify-between gap-3 space-y-0 p-4 pb-2">
          <div className="min-w-0">
            <p className="mb-1 flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-primary"><Sparkles className="h-3.5 w-3.5" />Pengenalan fitur · {currentStepIndex + 1}/{steps.length}</p>
            <h2 className="text-base font-semibold leading-snug">{currentStep.title}</h2>
          </div>
          <Button type="button" variant="ghost" size="icon" className="-mr-2 -mt-2 h-8 w-8 shrink-0" onClick={closeForNow} aria-label="Tutup pengenalan untuk sekarang">
            <X className="h-4 w-4" />
          </Button>
        </CardHeader>
        <CardContent className="space-y-3 px-4 pb-4 pt-1">
          <p className="text-sm leading-relaxed text-muted-foreground">{currentStep.description}</p>
          <div className="flex items-center justify-between gap-3">
            <Link to={currentStep.href} className="text-xs font-medium text-primary underline-offset-4 hover:underline">{currentStep.linkLabel}</Link>
            <div className="flex shrink-0 items-center gap-2">
              <Button type="button" variant="ghost" size="sm" className="h-9 px-2 text-xs" onClick={closeForNow}>Nanti</Button>
              <Button type="button" size="sm" className="h-9" onClick={advance}>
                {currentStepIndex === steps.length - 1 ? 'Selesai' : 'Berikutnya'}
                {currentStepIndex !== steps.length - 1 && <ArrowRight className="ml-1.5 h-3.5 w-3.5" />}
              </Button>
            </div>
          </div>
          <p className="text-[10px] text-muted-foreground">Tip yang sudah ditampilkan tidak akan diulang. Tip yang belum selesai dapat dilanjutkan saat aplikasi dibuka kembali.</p>
        </CardContent>
      </Card>
    </div>
  );
}
