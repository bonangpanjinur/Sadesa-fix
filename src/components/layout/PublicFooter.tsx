import { Link, useLocation } from 'react-router-dom';
import { useWhitelabel } from '@/hooks/useWhitelabel';
import { BUSINESS_PROFILE } from '@/config/businessProfile';

const PRIVATE_ROUTE_PREFIXES = ['/admin', '/merchant', '/courier', '/pos', '/verifikator', '/desa'];

export function PublicFooter() {
  const location = useLocation();
  const { settings } = useWhitelabel();

  if (PRIVATE_ROUTE_PREFIXES.some((prefix) => location.pathname === prefix || location.pathname.startsWith(`${prefix}/`))) {
    return null;
  }

  return (
    <footer className="mt-10 border-t border-orange-100 bg-[hsl(36_45%_98%)] px-4 py-8 text-muted-foreground">
      <div className="mx-auto flex max-w-6xl flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div className="space-y-2">
          <Link to="/" className="inline-flex items-center gap-2 text-sm font-bold text-foreground">
            <img src={settings.logoUrl || '/branding/sadesa-logo.webp'} alt={settings.siteName} className="h-7 w-auto max-w-[120px] object-contain" />
            <span>{settings.siteName}</span>
          </Link>
          <p className="max-w-md text-xs leading-relaxed">{settings.siteTagline}</p>
          {settings.companyLegalName && <p className="text-xs font-medium text-foreground">Dimiliki dan dioperasikan oleh {settings.companyLegalName}</p>}
        </div>
        <div className="text-xs sm:text-right">
          <div className="mb-2 flex flex-wrap gap-x-3 gap-y-1 sm:justify-end">
            <Link to="/about" className="font-medium hover:text-foreground hover:underline">Tentang Kami</Link>
            <Link to="/contact" className="font-medium hover:text-foreground hover:underline">Kontak</Link>
            <Link to="/products" className="hover:text-foreground hover:underline">Katalog</Link>
            <Link to="/ride" className="hover:text-foreground hover:underline">Layanan Antar</Link>
            <Link to="/checkout" className="hover:text-foreground hover:underline">Checkout</Link>
            <Link to="/privacy-policy" className="hover:text-foreground hover:underline">Kebijakan Privasi</Link>
            <Link to="/transaction-policy" className="hover:text-foreground hover:underline">Refund & Pengiriman</Link>
            <Link to="/terms" className="hover:text-foreground hover:underline">Syarat & Ketentuan</Link>
          </div>
          <p className="mb-1">{BUSINESS_PROFILE.email}{BUSINESS_PROFILE.phone ? ` · ${BUSINESS_PROFILE.phone}` : ''}</p>
          <p>© {new Date().getFullYear()} {settings.companyLegalName || settings.siteName}</p>
          <p className="mt-1">Seluruh hak cipta dilindungi.</p>
        </div>
      </div>
    </footer>
  );
}
