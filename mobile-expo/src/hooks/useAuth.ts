import { useAuthStore } from "@/stores/authStore";
import { isAppRole } from "@/lib/rbac";
import type { AppRole, MudbaseUser } from "@/api/schemas";

interface UseAuthReturn {
  user: MudbaseUser | null;
  role: AppRole | null;
  isOrganizer: boolean;
  isAttendee: boolean;
  isAuthenticated: boolean;
  isInitializing: boolean;
  isSubmitting: boolean;
  error: string | null;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => Promise<void>;
  clearError: () => void;
}

/** Thin selector hook over the auth store — screens read/act through this, never the store directly. */
export function useAuth(): UseAuthReturn {
  const user = useAuthStore((s) => s.user);
  const isInitializing = useAuthStore((s) => s.isInitializing);
  const isSubmitting = useAuthStore((s) => s.isSubmitting);
  const error = useAuthStore((s) => s.error);
  const login = useAuthStore((s) => s.login);
  const logout = useAuthStore((s) => s.logout);
  const clearError = useAuthStore((s) => s.clearError);

  const role = isAppRole(user?.customRole) ? user.customRole : null;

  return {
    user,
    role,
    isOrganizer: role === "organizer",
    isAttendee: role === "attendee",
    isAuthenticated: !!user,
    isInitializing,
    isSubmitting,
    error,
    login,
    logout,
    clearError,
  };
}
