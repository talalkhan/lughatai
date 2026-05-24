"use client";

import { useEffect, useState } from "react";

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

const DISMISSED_KEY = "lughatai_install_dismissed";
const VISIT_COUNT_KEY = "lughatai_visit_count";

export default function InstallPrompt() {
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [show, setShow] = useState(false);

  useEffect(() => {
    // Only show after 2+ visits and if not already dismissed
    const count = parseInt(localStorage.getItem(VISIT_COUNT_KEY) ?? "0") + 1;
    localStorage.setItem(VISIT_COUNT_KEY, String(count));

    if (localStorage.getItem(DISMISSED_KEY)) return;
    if (count < 2) return;

    const handler = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e as BeforeInstallPromptEvent);
      setShow(true);
    };

    window.addEventListener("beforeinstallprompt", handler);
    return () => window.removeEventListener("beforeinstallprompt", handler);
  }, []);

  async function handleInstall() {
    if (!deferredPrompt) return;
    await deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    if (outcome === "accepted") {
      localStorage.setItem(DISMISSED_KEY, "1");
    }
    setShow(false);
    setDeferredPrompt(null);
  }

  function handleDismiss() {
    localStorage.setItem(DISMISSED_KEY, "1");
    setShow(false);
  }

  if (!show) return null;

  return (
    <div
      role="dialog"
      aria-label="Install LughatAI app"
      className="fixed bottom-24 left-4 right-4 z-40 flex items-start gap-3 rounded-2xl border border-gray-200 bg-white p-4 shadow-xl dark:border-gray-700 dark:bg-gray-900 sm:bottom-4 sm:left-auto sm:right-4 sm:w-80"
    >
      <img
        src="/icons/icon-192.png"
        alt="LughatAI icon"
        width={48}
        height={48}
        className="rounded-xl shrink-0"
      />
      <div className="flex-1 min-w-0">
        <p className="font-semibold text-sm">Add LughatAI to Home Screen</p>
        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
          Instant access, works offline
        </p>
        <div className="flex gap-2 mt-3">
          <button
            onClick={handleInstall}
            className="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold rounded-lg min-h-[36px]"
          >
            Install
          </button>
          <button
            onClick={handleDismiss}
            className="px-3 py-1.5 text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 text-xs min-h-[36px]"
          >
            Not now
          </button>
        </div>
      </div>
      <button
        onClick={handleDismiss}
        aria-label="Close"
        className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 text-lg leading-none min-h-[44px] min-w-[44px] flex items-center justify-center -mt-1 -mr-1"
      >
        ×
      </button>
    </div>
  );
}
