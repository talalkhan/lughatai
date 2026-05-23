"use client";

import { useState } from "react";
import { useAuth } from "@/lib/auth";
import { flagWord } from "@/lib/api";

const REASONS = [
  { value: "translation", label: "Wrong translation" },
  { value: "example", label: "Bad example sentence" },
  { value: "poetry", label: "Poetry attribution" },
  { value: "other", label: "Other issue" },
] as const;

type Reason = (typeof REASONS)[number]["value"];

export default function FlagButton({ word }: { word: string }) {
  const { accessToken } = useAuth();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState<Reason>("translation");
  const [notes, setNotes] = useState("");
  const [status, setStatus] = useState<"idle" | "submitting" | "done">("idle");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setStatus("submitting");
    try {
      await flagWord(word, reason, notes || undefined, accessToken ?? undefined);
      setStatus("done");
      setTimeout(() => setOpen(false), 1500);
    } catch {
      setStatus("idle");
    }
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        aria-label="Report an error"
        className="inline-flex items-center gap-1.5 text-xs text-gray-400 hover:text-red-500 dark:hover:text-red-400 transition-colors min-h-[44px] px-2"
      >
        <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" d="M3 3l1.664 9.914M3 3h18M3 3l9 9m9-9l-1.664 9.914M21 3l-9 9m0 0l-6.336 3.086M12 12l6.336 3.086M5.664 12.914L12 12" />
        </svg>
        Report error
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4"
          onClick={e => { if (e.target === e.currentTarget) setOpen(false); }}
        >
          <div className="bg-white dark:bg-gray-900 rounded-2xl w-full max-w-sm p-6 shadow-xl">
            <h3 className="font-semibold text-lg mb-4">Report an error</h3>

            {status === "done" ? (
              <p className="text-emerald-600 dark:text-emerald-400 text-center py-4">
                Thanks for the feedback!
              </p>
            ) : (
              <form onSubmit={handleSubmit} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium mb-2 text-gray-700 dark:text-gray-300">
                    What's wrong?
                  </label>
                  <div className="space-y-2">
                    {REASONS.map(r => (
                      <label key={r.value} className="flex items-center gap-3 cursor-pointer min-h-[44px]">
                        <input
                          type="radio"
                          name="reason"
                          value={r.value}
                          checked={reason === r.value}
                          onChange={() => setReason(r.value)}
                          className="accent-emerald-600"
                        />
                        <span className="text-sm">{r.label}</span>
                      </label>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium mb-1 text-gray-700 dark:text-gray-300">
                    Notes (optional)
                  </label>
                  <textarea
                    value={notes}
                    onChange={e => setNotes(e.target.value)}
                    maxLength={500}
                    rows={3}
                    placeholder="Describe the issue…"
                    className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-emerald-500"
                  />
                </div>

                <div className="flex gap-3">
                  <button
                    type="button"
                    onClick={() => setOpen(false)}
                    className="flex-1 py-2.5 rounded-lg border border-gray-300 dark:border-gray-600 text-sm min-h-[44px]"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={status === "submitting"}
                    className="flex-1 py-2.5 rounded-lg bg-red-500 hover:bg-red-600 text-white text-sm font-semibold disabled:opacity-60 min-h-[44px]"
                  >
                    {status === "submitting" ? "Sending…" : "Submit"}
                  </button>
                </div>
              </form>
            )}
          </div>
        </div>
      )}
    </>
  );
}
