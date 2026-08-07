type AnalyticsProvider = "cloudflare" | "google";

type AnalyticsConfig = {
  provider: AnalyticsProvider;
  identifier: string;
};

declare global {
  interface Window {
    dataLayer?: unknown[];
    gtag?: (...args: unknown[]) => void;
  }
}

const ANALYTICS_META = 'meta[name="website:analytics"]';
const ANALYTICS_SCRIPT = "script[data-website-analytics]";

function readAnalyticsConfig(doc: Document): AnalyticsConfig | null {
  const meta = doc.querySelector<HTMLMetaElement>(ANALYTICS_META);
  const provider = meta?.dataset.provider;
  const identifier = meta?.content || "";
  if ((provider !== "cloudflare" && provider !== "google") ||
      !identifier || identifier !== identifier.trim() || identifier.length > 256) {
    return null;
  }
  return { provider, identifier };
}

function initialiseCloudflare(doc: Document, token: string): void {
  const script = doc.createElement("script");
  script.defer = true;
  script.src = "https://static.cloudflareinsights.com/beacon.min.js";
  script.dataset.cfBeacon = JSON.stringify({ token });
  script.dataset.websiteAnalytics = "cloudflare";
  doc.head.append(script);
}

function initialiseGoogle(doc: Document, measurementId: string): void {
  const view = doc.defaultView;
  if (!view) return;

  const script = doc.createElement("script");
  script.async = true;
  script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(measurementId)}`;
  script.dataset.websiteAnalytics = "google";
  doc.head.append(script);

  const dataLayer = view.dataLayer ||= [];
  const gtag = view.gtag ||= function (..._args: unknown[]): void {
    dataLayer.push(arguments);
  };
  gtag("js", new Date());
  gtag("config", measurementId);
}

export function initialiseAnalytics(doc: Document = document): void {
  const config = readAnalyticsConfig(doc);
  if (!config || doc.querySelector(ANALYTICS_SCRIPT)) return;

  try {
    if (config.provider === "cloudflare") initialiseCloudflare(doc, config.identifier);
    else initialiseGoogle(doc, config.identifier);
  } catch {
    // Content and navigation remain usable when a third-party script is blocked.
  }
}
