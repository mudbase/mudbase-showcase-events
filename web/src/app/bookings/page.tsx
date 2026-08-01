"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { useAuth } from "@/hooks/useAuth"
import { BookingList } from "@/components/bookings/BookingList"

export default function BookingsPage(): React.JSX.Element {
  const { isAuthenticated, loading } = useAuth()
  const router = useRouter()

  useEffect(() => {
    if (!loading && !isAuthenticated) router.replace("/login")
  }, [loading, isAuthenticated, router])

  if (loading || !isAuthenticated) {
    return <p className="container py-16 text-center text-sm text-muted-foreground">Loading…</p>
  }

  return (
    <div className="container max-w-2xl space-y-6 py-8">
      <h1 className="text-2xl font-semibold tracking-tight">My bookings</h1>
      <BookingList />
    </div>
  )
}
