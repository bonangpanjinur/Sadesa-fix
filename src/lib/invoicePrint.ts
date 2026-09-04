function printElement(element: HTMLElement | null, title: string, padding: string): void {
  if (!element) return;

  const printWindow = window.open('', '_blank');
  if (!printWindow) {
    alert('Popup diblokir. Izinkan popup untuk mencetak.');
    return;
  }

  printWindow.document.write(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>${title}</title>
      <style>
        body { margin: 0; padding: ${padding}; font-family: monospace; background: white; }
        @media print { body { padding: 0; } }
      </style>
    </head>
    <body>
      ${element.outerHTML}
      <script>
        window.onload = function() {
          window.print();
          window.onafterprint = function() { window.close(); };
        };
      </script>
    </body>
    </html>
  `);
  printWindow.document.close();
}

export function printInvoice(invoiceElement: HTMLElement | null): void {
  printElement(invoiceElement, 'Struk Pesanan', '20px');
}
