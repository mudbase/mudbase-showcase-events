"use client"

import { useState, useCallback } from "react"
import { useRouter } from "next/navigation"
import { useMudbase } from "@/lib/mudbase-provider"
import { MudbaseError, errorCode, type AppRole, type UserObject } from "@/lib/mudbase"

export interface RegisterResult {
  success: boolean
  /** true when the account was created but still needs email verification before it can log in. */
  requireVerification: boolean
}

interface UseAuthReturn {
  user: UserObject | null
  isAuthenticated: boolean
  /** The app-defined role slug for the signed-in user, or null when signed out. */
  role: AppRole | null
  isOrganizer: boolean
  isAttendee: boolean
  loading: boolean
  error: string | null
  register: (
    role: AppRole,
    email: string,
    password: string,
    firstName: string,
    lastName: string,
    agreedToTerms: boolean,
  ) => Promise<RegisterResult>
  login: (email: string, password: string, options?: { redirect?: boolean }) => Promise<boolean>
  logout: () => Promise<void>
  clearError: () => void
}

function isAppRole(value: string | null | undefined): value is AppRole {
  return value === "organizer" || value === "attendee"
}

export function useAuth(): UseAuthReturn {
  const { client, session, loading: sessionLoading, refreshSession } = useMudbase()
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const register = useCallback(
    async (
      role: AppRole,
      email: string,
      password: string,
      firstName: string,
      lastName: string,
      agreedToTerms: boolean,
    ): Promise<RegisterResult> => {
      setLoading(true)
      setError(null)
      try {
        const res = await client.register(role, { email, password, firstName, lastName, agreedToTerms })
        if (res.token) await refreshSession()
        return { success: true, requireVerification: res.requireVerification === true }
      } catch (err) {
        setError(err instanceof MudbaseError ? err.message : "Registration failed")
        return { success: false, requireVerification: false }
      } finally {
        setLoading(false)
      }
    },
    [client, refreshSession],
  )

  const login = useCallback(
    async (email: string, password: string, options?: { redirect?: boolean }): Promise<boolean> => {
      setLoading(true)
      setError(null)
      try {
        await client.login({ email, password })
        await refreshSession()
        if (options?.redirect !== false) {
          router.push("/")
        }
        return true
      } catch (err) {
        if (errorCode(err) === "EMAIL_VERIFICATION_REQUIRED") {
          setError("Please verify your email first - check your inbox for the verification link, then sign in.")
        } else {
          setError(err instanceof MudbaseError ? err.message : "Login failed")
        }
        return false
      } finally {
        setLoading(false)
      }
    },
    [client, router, refreshSession],
  )

  const logout = useCallback(async () => {
    setLoading(true)
    try {
      await client.logout()
      await refreshSession()
      router.push("/")
    } finally {
      setLoading(false)
    }
  }, [client, router, refreshSession])

  const user = session?.user ?? null
  const role = isAppRole(user?.customRole) ? user.customRole : null

  return {
    user,
    isAuthenticated: !!user,
    role,
    isOrganizer: role === "organizer",
    isAttendee: role === "attendee",
    loading: loading || sessionLoading,
    error,
    register,
    login,
    logout,
    clearError: () => setError(null),
  }
}
