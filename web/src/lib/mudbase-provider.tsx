"use client"

import React, { createContext, useContext, useEffect, useState, useCallback } from "react"
import { MudbaseClient, initMudbase, type MudbaseConfig, type SessionResponse } from "./mudbase"

interface MudbaseContextValue {
  client: MudbaseClient
  session: SessionResponse | null
  loading: boolean
  refreshSession: () => Promise<void>
}

const MudbaseContext = createContext<MudbaseContextValue | null>(null)

export function MudbaseProvider({
  children,
  config,
}: {
  children: React.ReactNode
  config: MudbaseConfig
}): React.JSX.Element {
  const [client] = useState<MudbaseClient>(() => initMudbase(config))
  const [session, setSession] = useState<SessionResponse | null>(null)
  const [loading, setLoading] = useState<boolean>(true)

  const refreshSession = useCallback(async (): Promise<void> => {
    try {
      const s = await client.getSession()
      setSession(s)
    } catch {
      setSession(null)
      client.clearToken()
    }
  }, [client])

  useEffect(() => {
    // Unlike the social showcase, this project has no public/anonymous role configured (see
    // plan/build-plan.md "Auth Flow") - there is nothing useful an anonymous session could read,
    // so we only ever try to restore a real, previously-issued token. No token means "signed out";
    // pages render their own sign-in prompt rather than the provider bootstrapping a guest session.
    const establish = async (): Promise<void> => {
      if (client.getToken()) {
        await refreshSession()
      }
      setLoading(false)
    }
    void establish()
  }, [client, refreshSession])

  return <MudbaseContext.Provider value={{ client, session, loading, refreshSession }}>{children}</MudbaseContext.Provider>
}

export function useMudbase(): MudbaseContextValue {
  const ctx = useContext(MudbaseContext)
  if (!ctx) throw new Error("useMudbase must be used inside <MudbaseProvider>")
  return ctx
}
