"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";
import { login, logout, refreshToken, register } from "./api";
import { AuthResult, UserDto } from "./types";

const ACCESS_TOKEN_KEY = "lughatai_access_token";
const REFRESH_TOKEN_KEY = "lughatai_refresh_token";

interface AuthState {
  user: UserDto | null;
  accessToken: string | null;
  isLoading: boolean;
}

interface AuthContextValue extends AuthState {
  login: (email: string, password: string) => Promise<void>;
  register: (username: string, email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<AuthState>({
    user: null,
    accessToken: null,
    isLoading: true,
  });

  // Rehydrate from localStorage on mount
  useEffect(() => {
    const stored = localStorage.getItem(ACCESS_TOKEN_KEY);
    const storedRefresh = localStorage.getItem(REFRESH_TOKEN_KEY);

    if (!stored || !storedRefresh) {
      setState(s => ({ ...s, isLoading: false }));
      return;
    }

    // Try to refresh (the access token might be expired)
    refreshToken(storedRefresh)
      .then(result => applyAuth(result))
      .catch(() => {
        // Refresh token expired — clear storage
        localStorage.removeItem(ACCESS_TOKEN_KEY);
        localStorage.removeItem(REFRESH_TOKEN_KEY);
        setState({ user: null, accessToken: null, isLoading: false });
      });
  }, []);

  const applyAuth = useCallback((result: AuthResult) => {
    localStorage.setItem(ACCESS_TOKEN_KEY, result.accessToken);
    localStorage.setItem(REFRESH_TOKEN_KEY, result.refreshToken);
    setState({ user: result.user, accessToken: result.accessToken, isLoading: false });
  }, []);

  const handleLogin = useCallback(async (email: string, password: string) => {
    const result = await login(email, password);
    applyAuth(result);
  }, [applyAuth]);

  const handleRegister = useCallback(
    async (username: string, email: string, password: string) => {
      const result = await register(username, email, password);
      applyAuth(result);
    },
    [applyAuth]
  );

  const handleLogout = useCallback(async () => {
    const storedRefresh = localStorage.getItem(REFRESH_TOKEN_KEY);
    if (storedRefresh) {
      await logout(storedRefresh).catch(() => {});
    }
    localStorage.removeItem(ACCESS_TOKEN_KEY);
    localStorage.removeItem(REFRESH_TOKEN_KEY);
    setState({ user: null, accessToken: null, isLoading: false });
  }, []);

  return (
    <AuthContext.Provider
      value={{
        ...state,
        login: handleLogin,
        register: handleRegister,
        logout: handleLogout,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
