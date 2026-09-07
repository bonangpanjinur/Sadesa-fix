import { useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";

type LaunchFileParams = {
  files: () => File[];
};

type LaunchQueueLike = {
  setConsumer: (consumer: (params: LaunchFileParams) => void) => void;
};

declare global {
  interface Window {
    launchQueue?: LaunchQueueLike;
  }
}

function CapabilityShell({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  return (
    <main className="min-h-screen bg-slate-50 px-4 py-12 text-slate-900">
      <section className="mx-auto max-w-2xl rounded-3xl bg-white p-6 shadow-sm sm:p-8">
        <p className="mb-3 text-sm font-semibold uppercase tracking-[0.18em] text-emerald-600">
          SaDesa PWA
        </p>
        <h1 className="text-2xl font-bold sm:text-3xl">{title}</h1>
        <p className="mt-3 text-slate-600">{description}</p>
        <div className="mt-6">{children}</div>
        <Link
          to="/"
          className="mt-8 inline-flex rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-700"
        >
          Kembali ke beranda
        </Link>
      </section>
    </main>
  );
}

export function PwaShareTargetPage() {
  const [searchParams] = useSearchParams();
  const title = searchParams.get("title");
  const text = searchParams.get("text");
  const url = searchParams.get("url");
  const hasContent = Boolean(title || text || url);

  return (
    <CapabilityShell
      title="Konten dibagikan ke SaDesa"
      description="SaDesa menerima konten yang Anda bagikan dari aplikasi lain."
    >
      {hasContent ? (
        <dl className="space-y-4 rounded-2xl bg-slate-50 p-4">
          {title && (
            <div>
              <dt className="text-xs font-semibold uppercase text-slate-500">Judul</dt>
              <dd className="mt-1 break-words">{title}</dd>
            </div>
          )}
          {text && (
            <div>
              <dt className="text-xs font-semibold uppercase text-slate-500">Pesan</dt>
              <dd className="mt-1 whitespace-pre-wrap break-words">{text}</dd>
            </div>
          )}
          {url && (
            <div>
              <dt className="text-xs font-semibold uppercase text-slate-500">Tautan</dt>
              <dd className="mt-1 break-all text-emerald-700">{url}</dd>
            </div>
          )}
        </dl>
      ) : (
        <p className="rounded-2xl bg-slate-50 p-4 text-slate-600">
          Belum ada konten yang dibagikan.
        </p>
      )}
    </CapabilityShell>
  );
}

export function PwaProtocolHandlerPage() {
  const [searchParams] = useSearchParams();
  const protocolUrl = searchParams.get("url");
  const parsedUrl = useMemo(() => {
    if (!protocolUrl) return null;
    try {
      return new URL(protocolUrl);
    } catch {
      return null;
    }
  }, [protocolUrl]);

  return (
    <CapabilityShell
      title="Tautan SaDesa diterima"
      description="SaDesa menerima tautan dari protocol web+sadesa."
    >
      {parsedUrl ? (
        <a
          href={parsedUrl.toString()}
          className="block break-all rounded-2xl bg-slate-50 p-4 text-emerald-700 underline"
        >
          {parsedUrl.toString()}
        </a>
      ) : (
        <p className="rounded-2xl bg-slate-50 p-4 text-slate-600">
          Tautan protocol tidak tersedia atau tidak valid.
        </p>
      )}
    </CapabilityShell>
  );
}

export function PwaFileHandlerPage() {
  const [files, setFiles] = useState<File[]>([]);
  const [preview, setPreview] = useState("");

  useEffect(() => {
    window.launchQueue?.setConsumer(({ files: getFiles }) => {
      setFiles(getFiles());
    });
  }, []);

  useEffect(() => {
    let cancelled = false;
    const file = files[0];
    if (!file) {
      setPreview("");
      return;
    }

    file
      .text()
      .then((content) => {
        if (!cancelled) setPreview(content.slice(0, 4000));
      })
      .catch(() => {
        if (!cancelled) setPreview("Isi file tidak dapat dibaca.");
      });

    return () => {
      cancelled = true;
    };
  }, [files]);

  return (
    <CapabilityShell
      title="File dibuka di SaDesa"
      description="SaDesa dapat menerima file JSON atau CSV dari sistem operasi."
    >
      {files.length > 0 ? (
        <div className="space-y-4">
          <div className="rounded-2xl bg-slate-50 p-4">
            <p className="font-semibold">{files[0].name}</p>
            <p className="mt-1 text-sm text-slate-500">
              {files[0].type || "Tipe file tidak diketahui"} · {files[0].size.toLocaleString("id-ID")} byte
            </p>
          </div>
          <pre className="max-h-80 overflow-auto whitespace-pre-wrap break-words rounded-2xl bg-slate-900 p-4 text-xs text-slate-100">
            {preview || "Membaca isi file…"}
          </pre>
        </div>
      ) : (
        <p className="rounded-2xl bg-slate-50 p-4 text-slate-600">
          Buka file JSON atau CSV menggunakan SaDesa untuk melihat pratinjaunya.
        </p>
      )}
    </CapabilityShell>
  );
}