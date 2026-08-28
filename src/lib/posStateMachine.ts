export type POSWorkflow = 'kds' | 'table' | 'return' | 'stock_transfer';

export const POS_WORKFLOW_TRANSITIONS: Record<POSWorkflow, Record<string, string[]>> = {
  kds: {
    pending: ['confirmed', 'cancelled'],
    confirmed: ['preparing', 'cancelled'],
    preparing: ['ready', 'cancelled'],
    ready: ['served', 'cancelled'],
    served: [],
    cancelled: [],
  },
  table: {
    available: ['reserved', 'occupied', 'cleaning'],
    reserved: ['occupied', 'available', 'cancelled'],
    occupied: ['cleaning', 'available'],
    cleaning: ['available'],
    cancelled: ['available'],
  },
  return: {
    draft: ['submitted', 'cancelled'],
    submitted: ['approved', 'rejected'],
    approved: ['completed'],
    rejected: [],
    completed: [],
    cancelled: [],
  },
  stock_transfer: {
    draft: ['submitted', 'cancelled'],
    submitted: ['approved', 'rejected'],
    approved: ['in_transit', 'cancelled'],
    in_transit: ['received', 'cancelled'],
    received: [],
    rejected: [],
    cancelled: [],
  },
};

export function canTransition(workflow: POSWorkflow, from: string, to: string): boolean {
  return POS_WORKFLOW_TRANSITIONS[workflow][from]?.includes(to) ?? false;
}

export function assertTransition(workflow: POSWorkflow, from: string, to: string): void {
  if (!canTransition(workflow, from, to)) {
    throw new Error(`Invalid ${workflow} transition: ${from} -> ${to}`);
  }
}

export function transition<T extends { status: string }>(workflow: POSWorkflow, entity: T, to: string): T {
  assertTransition(workflow, entity.status, to);
  return { ...entity, status: to };
}
