import { motion } from 'framer-motion';
import { CheckCircle, Package, Truck, MapPin, Clock, RotateCcw } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useTranslation, useFormatters, type TranslationKey } from '@/lib/i18n';

interface DeliveryStatus {
  status: 'NEW' | 'PROCESSING' | 'ASSIGNED' | 'COURIER_ACCEPTED' | 'PICKED_UP' | 'SENT' | 'ON_DELIVERY' | 'DELIVERING' | 'DELIVERED' | 'DONE';
  created_at: string;
  assigned_at?: string | null;
  picked_up_at?: string | null;
  delivered_at?: string | null;
  is_self_delivery?: boolean;
}

interface DeliveryStatusCardProps {
  order: DeliveryStatus;
  showEstimate?: boolean;
  refund?: {
    status: string;
    dispute_status?: string | null;
    settlement_status?: string | null;
  } | null;
}

const statusSteps: Array<{ key: string; labelKey: TranslationKey; icon: typeof Package }> = [
  { key: 'NEW', labelKey: 'order.step.created', icon: Package },
  { key: 'PROCESSED', labelKey: 'order.step.processed', icon: Clock },
  { key: 'ASSIGNED', labelKey: 'order.step.assigned', icon: Truck },
  { key: 'PICKED_UP', labelKey: 'order.step.picked_up', icon: MapPin },
  { key: 'DELIVERED', labelKey: 'order.step.delivered', icon: CheckCircle },
];

const statusOrder = ['NEW', 'PROCESSING', 'PROCESSED', 'READY', 'ASSIGNED', 'COURIER_ACCEPTED', 'PICKED_UP', 'SENT', 'ON_DELIVERY', 'DELIVERING', 'DELIVERED', 'DONE'];

export function DeliveryStatusCard({ order, showEstimate = true, refund }: DeliveryStatusCardProps) {
  const { t, tStatus } = useTranslation();
  const { formatTime } = useFormatters();
  const currentIndex = statusOrder.indexOf(order.status);

  const getStepTime = (stepKey: string): string | null => {
    switch (stepKey) {
      case 'NEW':
        return order.created_at;
      case 'PROCESSED':
        return null;
      case 'ASSIGNED':
        return order.assigned_at || null;
      case 'PICKED_UP':
        return order.picked_up_at || null;
      case 'DELIVERED':
        return order.delivered_at || null;
      default:
        return null;
    }
  };

  const isStepCompleted = (stepKey: string): boolean => {
    // ASSIGNED is the offer phase. It must not look like a confirmed
    // assignment until the courier explicitly accepts the offer.
    if (stepKey === 'ASSIGNED' && currentIndex < statusOrder.indexOf('COURIER_ACCEPTED')) {
      return false;
    }
    const stepIndex = statusOrder.indexOf(stepKey);
    return currentIndex >= stepIndex;
  };

  const isStepActive = (stepKey: string): boolean => {
    if ((order.status === 'ON_DELIVERY' || order.status === 'SENT' || order.status === 'DELIVERING') && stepKey === 'DELIVERED') {
      return true;
    }
    return order.status === stepKey && !(stepKey === 'ASSIGNED' && order.status === 'ASSIGNED');
  };

  const getEstimatedTime = () => {
    if (!order.picked_up_at) return null;
    const pickupTime = new Date(order.picked_up_at);
    const etaMin = new Date(pickupTime.getTime() + 20 * 60 * 1000);
    const etaMax = new Date(pickupTime.getTime() + 30 * 60 * 1000);
    return `${formatTime(etaMin)} - ${formatTime(etaMax)}`;
  };

  return (
    <div className="bg-card rounded-2xl p-5 border border-border">
      {/* Current Status Header */}
      <div className="flex items-center gap-3 mb-6">
        <div className={cn(
          "w-12 h-12 rounded-full flex items-center justify-center",
          order.status === 'DELIVERED' || order.status === 'DONE'
            ? 'bg-green-500'
            : 'bg-primary'
        )}>
          {order.status === 'DELIVERED' || order.status === 'DONE' ? (
            <CheckCircle className="h-6 w-6 text-white" />
          ) : order.status === 'COURIER_ACCEPTED' || order.status === 'ON_DELIVERY' || order.status === 'SENT' || order.status === 'PICKED_UP' || order.status === 'DELIVERING' ? (
            <Truck className="h-6 w-6 text-white" />
          ) : (
            <Package className="h-6 w-6 text-white" />
          )}
        </div>
        <div className="flex-1">
          <p className="font-bold text-lg">{tStatus(order.status)}</p>
          {showEstimate && (order.status === 'ON_DELIVERY' || order.status === 'SENT' || order.status === 'DELIVERING') && getEstimatedTime() && (
            <p className="text-sm text-muted-foreground flex items-center gap-1">
              <Clock className="h-3.5 w-3.5" />
              {t('order.eta.label')}: {getEstimatedTime()}
            </p>
          )}
        </div>
      </div>

      {/* Progress Steps */}
      <div className="space-y-0">
        {statusSteps.map((step, index) => {
          const isCompleted = isStepCompleted(step.key);
          const isActive = isStepActive(step.key);
          const stepTime = getStepTime(step.key);
          const StepIcon = step.icon;

          return (
            <motion.div
              key={step.key}
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: index * 0.1 }}
              className="flex min-w-0 items-start gap-3"
            >
              <div className="flex flex-col items-center">
                <div
                  className={cn(
                    "w-10 h-10 rounded-full flex items-center justify-center transition-all",
                    isCompleted
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-muted text-muted-foreground'
                  )}
                >
                  {isCompleted ? (
                    <CheckCircle className="h-5 w-5" />
                  ) : (
                    <StepIcon className="h-5 w-5" />
                  )}
                </div>
                {index < statusSteps.length - 1 && (
                  <div
                    className={cn(
                      "w-0.5 h-10 transition-all",
                      isCompleted ? 'bg-primary' : 'bg-muted'
                    )}
                  />
                )}
              </div>

              <div className="min-w-0 flex-1 pb-4">
                <p
                  className={cn(
                    "font-medium",
                    isCompleted ? 'text-foreground' : 'text-muted-foreground'
                  )}
                >
                  {t(step.labelKey)}
                </p>
                {stepTime && (
                  <p className="text-sm text-muted-foreground">
                    {formatTime(stepTime)}
                  </p>
                )}
                {isActive && !isCompleted && (
                  <span className="inline-flex items-center gap-1 text-xs text-primary mt-1">
                    <span className="w-1.5 h-1.5 bg-primary rounded-full animate-pulse" />
                    {t('order.step.inProgress')}
                  </span>
                )}
              </div>
            </motion.div>
          );
        })}
        {refund && (() => {
          const rejected = refund.status === 'REJECTED' || refund.dispute_status === 'RESOLVED_REJECTED';
          const completed = refund.settlement_status === 'COMPLETED';
          const approved = refund.status === 'APPROVED';
          const label = rejected ? 'Refund Ditolak' : completed ? 'Refund Selesai' : approved ? 'Refund Diproses' : 'Pengajuan Refund';
          const description = rejected
            ? 'Permintaan refund ditolak oleh admin'
            : completed
              ? 'Dana refund sudah berhasil dicairkan'
              : approved
                ? refund.settlement_status === 'FAILED'
                  ? 'Pencairan gagal dan perlu ditindaklanjuti'
                  : 'Refund disetujui, menunggu pencairan dana'
                : 'Permintaan refund sedang ditinjau';
          return (
            <div className="flex min-w-0 items-start gap-3">
              <div className="flex flex-col items-center">
                <div className={cn(
                  'w-10 h-10 rounded-full flex items-center justify-center transition-all',
                  rejected || completed ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'
                )}>
                  {rejected || completed ? <CheckCircle className="h-5 w-5" /> : <RotateCcw className="h-5 w-5" />}
                </div>
              </div>
              <div className="min-w-0 flex-1 pb-4">
                <p className={cn('font-medium', rejected || completed ? 'text-foreground' : 'text-muted-foreground')}>{label}</p>
                <p className="text-xs text-muted-foreground mt-1">{description}</p>
                {!rejected && !completed && (
                  <span className="inline-flex items-center gap-1 text-xs text-primary mt-1">
                    <span className="w-1.5 h-1.5 bg-primary rounded-full animate-pulse" />
                    Sedang diproses
                  </span>
                )}
              </div>
            </div>
          );
        })()}
      </div>
    </div>
  );
}
