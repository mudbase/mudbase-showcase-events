import type { Metadata } from "next"
import { MudbaseProvider } from "@/lib/mudbase-provider"
import { QueryProvider } from "@/components/providers/QueryProvider"
import { Header } from "@/components/layout/Header"
import { MUDBASE_PROJECT_ID, MUDBASE_URL } from "@/lib/config"
import "./globals.css"

export const metadata: Metadata = {
  title: {
    template: "%s | Mudbase Showcase - Events",
    default: "Mudbase Showcase - Events",
  },
  description:
    "An event booking/ticketing platform built entirely on Mudbase - multi-role auth, capacity-aware booking, waitlisting, and QR check-in, with zero custom backend.",
}

export default function RootLayout({ children }: { children: React.ReactNode }): React.JSX.Element {
  return (
    <html lang="en">
      <body>
        <QueryProvider>
          <MudbaseProvider config={{ projectId: MUDBASE_PROJECT_ID, baseUrl: MUDBASE_URL }}>
            <div className="flex min-h-screen flex-col">
              <Header />
              <main className="flex-1">{children}</main>
              <footer className="border-t border-border py-8 text-center text-sm text-muted-foreground">
                Built entirely on{" "}
                <a href="https://www.mudbase.dev" className="underline underline-offset-4" target="_blank" rel="noreferrer">
                  Mudbase
                </a>{" "}
                - no custom backend.
              </footer>
            </div>
          </MudbaseProvider>
        </QueryProvider>
      </body>
    </html>
  )
}
