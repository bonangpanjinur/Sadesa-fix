import { useCallback, useState } from 'react';

export interface POSPaymentState {
  paymentMethod: string;
  paymentAmount: string;
  isSplitPayment: boolean;
  splitMethod2: string;
  splitAmount1: string;
  splitAmount2: string;
  paymentDialog: boolean;
  successDialog: boolean;
}

export function usePOSPayment(total: number, cartLength: number) {
  const [paymentMethod, setPaymentMethod] = useState('cash');
  const [paymentAmount, setPaymentAmount] = useState('');
  const [isSplitPayment, setIsSplitPayment] = useState(false);
  const [splitMethod2, setSplitMethod2] = useState('transfer');
  const [splitAmount1, setSplitAmount1] = useState('');
  const [splitAmount2, setSplitAmount2] = useState('');
  const [paymentDialog, setPaymentDialog] = useState(false);
  const [successDialog, setSuccessDialog] = useState(false);

  const openPayment = useCallback(() => {
    if (cartLength === 0) return false;
    setPaymentAmount(String(total));
    setPaymentDialog(true);
    return true;
  }, [cartLength, total]);

  const handlePaymentChange = useCallback((field: string, value: string | boolean) => {
    switch (field) {
      case 'paymentMethod': setPaymentMethod(String(value)); break;
      case 'paymentAmount': setPaymentAmount(String(value)); break;
      case 'isSplitPayment': setIsSplitPayment(value === 'true' || value === true); break;
      case 'splitMethod2': setSplitMethod2(String(value)); break;
      case 'splitAmount1': setSplitAmount1(String(value)); break;
      case 'splitAmount2': setSplitAmount2(String(value)); break;
      default: break;
    }
  }, []);

  const resetPayment = useCallback(() => {
    setPaymentAmount('');
    setPaymentDialog(false);
    setSuccessDialog(false);
    setIsSplitPayment(false);
    setSplitAmount1('');
    setSplitAmount2('');
  }, []);

  return {
    paymentMethod, setPaymentMethod,
    paymentAmount, setPaymentAmount,
    isSplitPayment, setIsSplitPayment,
    splitMethod2, setSplitMethod2,
    splitAmount1, setSplitAmount1,
    splitAmount2, setSplitAmount2,
    paymentDialog, setPaymentDialog,
    successDialog, setSuccessDialog,
    openPayment, handlePaymentChange, resetPayment,
  };
}
