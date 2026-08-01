import { create } from "zustand";
import { mudbaseClient, MudbaseApiError } from "@/api/client";
import type { MudbaseUser } from "@/api/schemas";

interface AuthState {
  user: MudbaseUser | null;
  /** True only while the boot-time restoreTokens()+getSession() sequence is running. */
  isInitializing: boolean;
  isSubmitting: boolean;
  error: string | null;
  initialize: () => Promise<void>;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => Promise<void>;
  clearError: () => void;
}

function messageFrom(err: unknown, fallback: string): string {
  return err instanceof MudbaseApiError ? err.message : fallback;
}

/**
 * A plain in-memory zustand store, not persisted via MMKV/AsyncStorage — the
 * only durable state is the token pair in SecureStore (mudbaseClient owns
 * that). There is **no anonymous-session fallback** here — this app's Mudbase
 * collections require a real authenticated JWT for every role, including the
 * attendee (see plan/build-plan.md "Auth Flow"). A cold start with no valid
 * tokens, or a session that fails to restore, simply leaves `user: null` and
 * the root navigator redirects to `/login` — mirroring
 * web/src/lib/mudbase-provider.tsx's own "no anonymous fallback" bootstrap.
 */
export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  isInitializing: true,
  isSubmitting: false,
  error: null,

  initialize: async (): Promise<void> => {
    set({ isInitializing: true });
    const hasTokens = await mudbaseClient.restoreTokens();
    if (hasTokens) {
      const user = await mudbaseClient.getSession();
      if (user) {
        set({ user, isInitializing: false });
        return;
      }
    }
    // No tokens, or a restored session that failed to validate — no fallback session exists in
    // this app. The root navigator sends the user to /login.
    set({ user: null, isInitializing: false });
  },

  login: async (email, password): Promise<boolean> => {
    set({ isSubmitting: true, error: null });
    try {
      const user = await mudbaseClient.login(email, password);
      set({ user, isSubmitting: false });
      return true;
    } catch (err) {
      set({ error: messageFrom(err, "Login failed. Check your email and password."), isSubmitting: false });
      return false;
    }
  },

  logout: async (): Promise<void> => {
    set({ isSubmitting: true });
    await mudbaseClient.logout();
    set({ user: null, isSubmitting: false });
  },

  clearError: (): void => set({ error: null }),
}));
