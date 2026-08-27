-- Cleanup transaction_packages table
-- Remove unused column price_per_transaction as it's replaced by total_price
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='transaction_packages' AND column_name='price_per_transaction') THEN
        ALTER TABLE public.transaction_packages DROP COLUMN price_per_transaction;
    END IF;
END $$;

-- Ensure package columns are adjusted only after the package table exists.
DO $$
BEGIN
    IF to_regclass('public.transaction_packages') IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'transaction_packages'
             AND column_name = 'kas_fee'
       ) THEN
        ALTER TABLE public.transaction_packages
        ALTER COLUMN kas_fee TYPE NUMERIC(5,2);
        COMMENT ON TABLE public.transaction_packages IS 'Paket kuota transaksi yang dapat dibeli oleh merchant. Jumlah kuota yang dikonsumsi per transaksi diatur di tabel quota_tiers.';
    END IF;
END $$;
