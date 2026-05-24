"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import SearchBar from "@/components/SearchBar";
import { useAuth } from "@/lib/auth";

type NavItem = {
  href: string;
  label: string;
  shortLabel: string;
  icon: string;
};

const DESKTOP_NAV: NavItem[] = [
  { href: "/browse", label: "Browse", shortLabel: "Browse", icon: "◫" },
  { href: "/favorites", label: "Favorites", shortLabel: "Saved", icon: "♥" },
  { href: "/history", label: "History", shortLabel: "History", icon: "↺" },
  { href: "/flashcards", label: "Flashcards", shortLabel: "Study", icon: "◈" },
  { href: "/quiz", label: "Quiz", shortLabel: "Quiz", icon: "?" },
];

const MOBILE_NAV: NavItem[] = [
  { href: "/", label: "Home", shortLabel: "Home", icon: "⌂" },
  { href: "/browse", label: "Browse", shortLabel: "Browse", icon: "◫" },
  { href: "/favorites", label: "Favorites", shortLabel: "Saved", icon: "♥" },
  { href: "/flashcards", label: "Flashcards", shortLabel: "Study", icon: "◈" },
];

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(`${href}/`);
}

function NavLink({
  item,
  pathname,
  mobile = false,
}: {
  item: NavItem;
  pathname: string;
  mobile?: boolean;
}) {
  const active = isActive(pathname, item.href);

  if (mobile) {
    return (
      <Link
        href={item.href}
        aria-current={active ? "page" : undefined}
        className={`flex min-h-[56px] flex-1 flex-col items-center justify-center gap-1 rounded-2xl px-2 text-[11px] font-medium transition-colors ${
          active
            ? "bg-indigo-600 text-white shadow-sm"
            : "text-gray-500 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800"
        }`}
      >
        <span className="text-base leading-none">{item.icon}</span>
        <span>{item.shortLabel}</span>
      </Link>
    );
  }

  return (
    <Link
      href={item.href}
      aria-current={active ? "page" : undefined}
      className={`rounded-full px-3 py-2 text-sm font-medium transition-colors ${
        active
          ? "bg-indigo-600 text-white"
          : "text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-white"
      }`}
    >
      {item.label}
    </Link>
  );
}

export default function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { user, logout, isLoading } = useAuth();

  const hideChrome = pathname === "/auth";
  const showHeaderSearch = !hideChrome && pathname !== "/";
  const pagePadding = hideChrome ? "" : "pb-24 md:pb-0";

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top,_rgba(99,102,241,0.14),_transparent_30%),linear-gradient(180deg,_#ffffff_0%,_#f8fafc_52%,_#ffffff_100%)] dark:bg-[radial-gradient(circle_at_top,_rgba(79,70,229,0.2),_transparent_28%),linear-gradient(180deg,_#030712_0%,_#09111f_48%,_#030712_100%)]">
      {!hideChrome && (
        <header className="sticky top-0 z-40 border-b border-gray-200/70 bg-white/85 backdrop-blur-xl dark:border-gray-800/70 dark:bg-gray-950/80">
          <div className="mx-auto max-w-6xl px-4">
            <div className="flex items-center gap-4 py-3">
              <Link href="/" className="min-w-0 shrink-0">
                <div className="text-lg font-semibold tracking-tight text-gray-950 dark:text-white">
                  UrduMeaning
                </div>
                <p className="hidden text-xs text-gray-500 dark:text-gray-400 sm:block">
                  English to Urdu dictionary, with context and memory hooks
                </p>
              </Link>

              <nav className="hidden items-center gap-1 lg:flex">
                {DESKTOP_NAV.map((item) => (
                  <NavLink key={item.href} item={item} pathname={pathname} />
                ))}
              </nav>

              <div className="ml-auto flex items-center gap-2">
                {!isLoading && user ? (
                  <>
                    <div className="hidden rounded-full border border-gray-200 bg-white px-3 py-2 text-right dark:border-gray-700 dark:bg-gray-900 sm:block">
                      <p className="text-xs font-semibold text-gray-900 dark:text-gray-100">
                        {user.username}
                      </p>
                      <p className="text-[11px] uppercase tracking-wide text-emerald-600 dark:text-emerald-400">
                        {user.tier}
                      </p>
                    </div>
                    <button
                      onClick={() => logout()}
                      className="min-h-[44px] rounded-full border border-gray-200 px-4 text-sm font-medium text-gray-600 transition-colors hover:bg-gray-100 hover:text-gray-900 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-white"
                    >
                      Sign out
                    </button>
                  </>
                ) : (
                  <Link
                    href="/auth"
                    className="inline-flex min-h-[44px] items-center rounded-full border border-gray-200 px-4 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-100 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-800"
                  >
                    Sign in
                  </Link>
                )}
              </div>
            </div>

            {showHeaderSearch && (
              <div className="pb-3">
                <SearchBar variant="compact" />
              </div>
            )}
          </div>
        </header>
      )}

      <div className={pagePadding}>{children}</div>

      {!hideChrome && (
        <nav className="fixed inset-x-0 bottom-0 z-40 border-t border-gray-200/80 bg-white/92 px-3 py-3 backdrop-blur-xl dark:border-gray-800/80 dark:bg-gray-950/92 lg:hidden">
          <div className="mx-auto flex max-w-md items-center gap-2">
            {MOBILE_NAV.map((item) => (
              <NavLink key={item.href} item={item} pathname={pathname} mobile />
            ))}
          </div>
        </nav>
      )}
    </div>
  );
}
